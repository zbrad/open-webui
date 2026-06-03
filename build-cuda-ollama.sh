#!/usr/bin/env bash
# Build open-webui with CUDA cu133 and upstream Ollama (downloaded via install.sh).

set -euo pipefail

CUDA_VER="${CUDA_VER:-cu133}"
IMAGE_TAG="${IMAGE_TAG:-open-webui:cuda133-ollama}"

echo "Building ${IMAGE_TAG} with upstream Ollama"

docker build \
    --build-arg USE_CUDA=true \
    --build-arg USE_CUDA_VER="${CUDA_VER}" \
    --build-arg USE_OLLAMA=true \
    -t "${IMAGE_TAG}" \
    "${@}" \
    .

echo "Done: ${IMAGE_TAG}"
