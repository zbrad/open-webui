<script lang="ts">
	import { toast } from 'svelte-sonner';
	import { onMount, onDestroy, getContext } from 'svelte';

	import {
		getModelServices,
		startModelService,
		stopModelService,
		type ModelServiceEntry,
		type SystemMemory
	} from '$lib/apis/modelServices';

	import Spinner from '$lib/components/common/Spinner.svelte';

	const i18n = getContext('i18n');

	let loading = true;
	let entries: ModelServiceEntry[] = [];
	let systemMemory: SystemMemory = { total_bytes: null, available_bytes: null };
	let pendingActions: Record<string, boolean> = {};

	let pollInterval: ReturnType<typeof setInterval> | undefined;

	const formatGiB = (bytes: number | null | undefined) => {
		if (bytes === null || bytes === undefined) return '—';
		return `${(bytes / 1024 ** 3).toFixed(1)} GiB`;
	};

	const refresh = async () => {
		const res = await getModelServices(localStorage.token).catch((err) => {
			toast.error(`${err}`);
			return null;
		});

		if (res) {
			entries = res.data;
			systemMemory = res.system_memory;
		}

		loading = false;
	};

	const startHandler = async (name: string) => {
		pendingActions = { ...pendingActions, [name]: true };

		await startModelService(localStorage.token, name)
			.then(() => {
				toast.success($i18n.t('Started "{{name}}"', { name }));
			})
			.catch((err) => {
				toast.error(`${err}`);
			});

		pendingActions = { ...pendingActions, [name]: false };
		await refresh();
	};

	const stopHandler = async (name: string) => {
		pendingActions = { ...pendingActions, [name]: true };

		await stopModelService(localStorage.token, name)
			.then(() => {
				toast.success($i18n.t('Stopped "{{name}}"', { name }));
			})
			.catch((err) => {
				toast.error(`${err}`);
			});

		pendingActions = { ...pendingActions, [name]: false };
		await refresh();
	};

	onMount(() => {
		refresh();
		pollInterval = setInterval(refresh, 10000);
	});

	onDestroy(() => {
		if (pollInterval) clearInterval(pollInterval);
	});
</script>

<div class="flex flex-col h-full justify-between text-sm">
	<div class="overflow-y-scroll scrollbar-hidden h-full">
		<div class="flex flex-col gap-1 mb-3">
			<div class="text-sm font-medium">{$i18n.t('System Memory')}</div>
			<div class="text-xs text-gray-500">
				{formatGiB(systemMemory.available_bytes)} {$i18n.t('available')} / {formatGiB(
					systemMemory.total_bytes
				)}
				{$i18n.t('total')}
			</div>
		</div>

		{#if loading}
			<div class="flex justify-center py-6">
				<Spinner />
			</div>
		{:else if entries.length === 0}
			<div class="text-xs text-gray-500 py-4">
				{$i18n.t('No known model services. Check the aliases file path in the launcher config.')}
			</div>
		{:else}
			<div class="overflow-x-auto">
				<table class="w-full text-xs text-left">
					<thead>
						<tr class="text-gray-500 border-b dark:border-gray-850">
							<th class="py-1.5 pr-2 font-medium">{$i18n.t('Model')}</th>
							<th class="py-1.5 pr-2 font-medium">{$i18n.t('Status')}</th>
							<th class="py-1.5 pr-2 font-medium">{$i18n.t('Disk Size')}</th>
							<th class="py-1.5 pr-2 font-medium">{$i18n.t('Live Memory')}</th>
							<th class="py-1.5 pr-2 font-medium"></th>
						</tr>
					</thead>
					<tbody>
						{#each entries as entry (entry.name)}
							<tr class="border-b dark:border-gray-850">
								<td class="py-2 pr-2">
									<div class="font-medium">{entry.alias}</div>
									<div class="text-gray-500">{entry.port ? `:${entry.port}` : ''}</div>
								</td>
								<td class="py-2 pr-2">
									<span
										class="px-1.5 py-0.5 rounded-full text-[0.65rem] font-medium {entry.active
											? 'bg-green-500/20 text-green-700 dark:text-green-400'
											: 'bg-gray-500/20 text-gray-600 dark:text-gray-400'}"
									>
										{entry.active ? $i18n.t('running') : $i18n.t('stopped')}
									</span>
								</td>
								<td class="py-2 pr-2">{formatGiB(entry.size_bytes)}</td>
								<td class="py-2 pr-2">
									{entry.active ? formatGiB(entry.memory_current_bytes) : '—'}
								</td>
								<td class="py-2 pr-2 text-right">
									{#if pendingActions[entry.name]}
										<Spinner className="size-4" />
									{:else if entry.active}
										<button
											class="px-2 py-1 rounded-lg bg-gray-100 dark:bg-gray-800 hover:bg-gray-200 dark:hover:bg-gray-700 transition"
											on:click={() => stopHandler(entry.name)}
										>
											{$i18n.t('Stop')}
										</button>
									{:else}
										<button
											class="px-2 py-1 rounded-lg bg-gray-100 dark:bg-gray-800 hover:bg-gray-200 dark:hover:bg-gray-700 transition"
											on:click={() => startHandler(entry.name)}
										>
											{$i18n.t('Start')}
										</button>
									{/if}
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
	</div>
</div>
