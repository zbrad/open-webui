#!/usr/bin/env bash
# Build open-webui with CUDA cu133 and local ollama-server-spark binary.
# Requires: docker buildx, ../ollama/ollama-server-spark

set -euo pipefail

OLLAMA_BIN="${OLLAMA_BIN:-ollama-server-spark}"
OLLAMA_DIR="${OLLAMA_DIR:-../ollama}"
CUDA_VER="${CUDA_VER:-cu133}"
IMAGE_TAG="${IMAGE_TAG:-open-webui:cuda133-spark}"

if [ ! -f "${OLLAMA_DIR}/${OLLAMA_BIN}" ]; then
    echo "ERROR: ${OLLAMA_DIR}/${OLLAMA_BIN} not found" >&2
    exit 1
fi

echo "Building ${IMAGE_TAG} with local ${OLLAMA_BIN} from ${OLLAMA_DIR}"

docker buildx build \
    --build-arg USE_CUDA=true \
    --build-arg USE_CUDA_VER="${CUDA_VER}" \
    --build-arg USE_OLLAMA=true \
    --build-arg USE_LOCAL_OLLAMA=true \
    --build-arg LOCAL_OLLAMA_BIN="${OLLAMA_BIN}" \
    --build-context ollama-local="${OLLAMA_DIR}" \
    -t "${IMAGE_TAG}" \
    "${@}" \
    .

echo "Done: ${IMAGE_TAG}"
