"""Admin control over local llama.cpp model servers.

Deliberately thin: this router never reimplements a launcher script's
alias-resolution or launch-flag logic. It reads the launcher's own model
catalog (a JSON alias table) read-only, queries `systemctl --user` for live
state/memory of any matching unit, and shells out to the launcher itself for
start/stop -- so the launcher stays the single source of truth for how a
model is actually invoked.

Routes:
  GET  /                  — catalog + status + memory, one row per known model
  POST /{name}/start      — start a model's systemd --user service
  POST /{name}/stop       — stop a model's systemd --user service
"""

import asyncio
import json
import logging
import os
import re

from fastapi import APIRouter, Depends, HTTPException, Request
from open_webui.utils.auth import get_admin_user

log = logging.getLogger(__name__)

router = APIRouter()

# Unit names are always derived from an alias already present in the parsed
# catalog (never from raw client input), but keep an explicit allowlist
# pattern as a second line of defense before any subprocess is built.
_ALIAS_RE = re.compile(r'^[A-Za-z0-9_-]+$')


def _load_catalog(aliases_path: str) -> dict:
    """Parse the launcher's alias table. Read-only: mirrors just enough of
    its `search_paths` resolution to locate each GGUF for a disk-size figure
    -- no launch-flag logic lives here.
    """
    if not os.path.isfile(aliases_path):
        raise HTTPException(status_code=500, detail=f'Aliases file not found: {aliases_path}')

    try:
        with open(aliases_path, encoding='utf-8') as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        raise HTTPException(status_code=500, detail=f'Failed to read aliases file: {e}') from e

    search_paths = [os.path.expanduser(p) for p in data.get('search_paths', [])]
    models = data.get('models', {})

    catalog = {}
    for name, entry in models.items():
        if not _ALIAS_RE.match(name):
            log.warning('Skipping model_services catalog entry with unsafe name: %r', name)
            continue

        alias = entry.get('alias', name)
        filename = entry.get('filename', '')
        resolved_path = None
        for d in search_paths:
            candidate = os.path.join(d, filename)
            if os.path.isfile(candidate):
                resolved_path = candidate
                break

        catalog[name] = {
            'name': name,
            'alias': alias,
            'unit': f'nemo-{alias}.service',
            'port': entry.get('port'),
            'path': resolved_path,
            'size_bytes': os.path.getsize(resolved_path) if resolved_path else None,
        }

    return catalog


async def _run(*args: str) -> tuple[int, str, str]:
    proc = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await proc.communicate()
    return proc.returncode, stdout.decode(errors='replace'), stderr.decode(errors='replace')


async def _unit_state(unit: str) -> dict:
    """Live status + cgroup memory for one systemd --user unit. Returns
    conservative defaults ('inactive'/None) for a unit that doesn't exist
    yet (never started) rather than erroring -- that's a normal state here.
    """
    rc, out, _ = await _run('systemctl', '--user', 'is-active', unit)
    active_state = out.strip() or 'inactive'

    rc, out, _ = await _run(
        'systemctl', '--user', 'show', unit, '-p', 'MemoryCurrent', '-p', 'MemoryPeak', '--value'
    )
    values = out.strip().split('\n') if out.strip() else []
    mem_current = _parse_mem_value(values[0]) if len(values) > 0 else None
    mem_peak = _parse_mem_value(values[1]) if len(values) > 1 else None

    return {
        'active': active_state == 'active',
        'state': active_state,
        'memory_current_bytes': mem_current,
        'memory_peak_bytes': mem_peak,
    }


def _parse_mem_value(value: str) -> int | None:
    value = value.strip()
    if not value or value == '[not set]':
        return None
    try:
        return int(value)
    except ValueError:
        return None


def _system_memory() -> dict:
    """Total/available system memory from /proc/meminfo -- correct source
    for unified-memory hosts (e.g. GB10), where `nvidia-smi` reports no
    separate GPU memory figure at all.
    """
    total_kib = avail_kib = None
    try:
        with open('/proc/meminfo', encoding='utf-8') as f:
            for line in f:
                if line.startswith('MemTotal:'):
                    total_kib = int(line.split()[1])
                elif line.startswith('MemAvailable:'):
                    avail_kib = int(line.split()[1])
    except OSError:
        pass

    return {
        'total_bytes': total_kib * 1024 if total_kib is not None else None,
        'available_bytes': avail_kib * 1024 if avail_kib is not None else None,
    }


def _require_enabled(request: Request) -> None:
    if not request.app.state.config.MODEL_SERVICES_ENABLE:
        raise HTTPException(status_code=503, detail='Model services are disabled')


@router.get('/')
async def list_model_services(request: Request, user=Depends(get_admin_user)):
    _require_enabled(request)

    aliases_path = request.app.state.config.MODEL_SERVICES_ALIASES_PATH
    catalog = _load_catalog(aliases_path)

    states = await asyncio.gather(*(_unit_state(entry['unit']) for entry in catalog.values()))

    data = []
    for entry, state in zip(catalog.values(), states):
        data.append({**entry, **state})

    return {'data': data, 'system_memory': _system_memory()}


async def _resolve_entry(request: Request, name: str) -> dict:
    aliases_path = request.app.state.config.MODEL_SERVICES_ALIASES_PATH
    catalog = _load_catalog(aliases_path)
    entry = catalog.get(name)
    if entry is None:
        raise HTTPException(status_code=404, detail=f'Unknown model service: {name}')
    return entry


@router.post('/{name}/start')
async def start_model_service(request: Request, name: str, user=Depends(get_admin_user)):
    _require_enabled(request)
    await _resolve_entry(request, name)  # validate against the catalog before touching a subprocess

    launcher = request.app.state.config.MODEL_SERVICES_LAUNCHER_PATH
    if not os.path.isfile(launcher):
        raise HTTPException(status_code=500, detail=f'Launcher not found: {launcher}')

    rc, out, err = await _run(launcher, '--model', name, 'start')
    if rc != 0:
        raise HTTPException(status_code=400, detail=(err or out or 'start failed').strip())
    return {'ok': True, 'output': out.strip()}


@router.post('/{name}/stop')
async def stop_model_service(request: Request, name: str, user=Depends(get_admin_user)):
    _require_enabled(request)
    await _resolve_entry(request, name)  # validate against the catalog before touching a subprocess

    launcher = request.app.state.config.MODEL_SERVICES_LAUNCHER_PATH
    if not os.path.isfile(launcher):
        raise HTTPException(status_code=500, detail=f'Launcher not found: {launcher}')

    rc, out, err = await _run(launcher, '--model', name, 'stop')
    if rc != 0:
        raise HTTPException(status_code=400, detail=(err or out or 'stop failed').strip())
    return {'ok': True, 'output': out.strip()}
