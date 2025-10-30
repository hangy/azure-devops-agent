#!/bin/bash

set -euo pipefail

# High-level: build base image with local-build.sh, tag as agent-base-image:latest, then bake capability targets.

REGISTRY="${REGISTRY:-agent}"          # Only used if pushing manually later
TAG="${TAG:-latest}"                   # Not directly used by bake unless we extend tags
VSTS_AGENT_VERSION="${VSTS_AGENT_VERSION:-4.261.0}" # Example version override

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${SCRIPT_DIR}"
K8S_DIR="${BASE_DIR}/azure-devops-agent-on-kubernetes"

echo "[info] Building base image via local-build.sh..."
pushd "${K8S_DIR}" >/dev/null
REGISTRY=tmp TAG=base ./local-build.sh >/dev/null
popd >/dev/null

# Ensure buildx builder exists
if ! docker buildx inspect bake-builder >/dev/null 2>&1; then
    echo "[info] Creating buildx builder 'bake-builder'"
    docker buildx create --name bake-builder --use >/dev/null
fi

# Allow specifying targets as script args; default builds all (group default)
TARGETS=("$@")
SET_ARGS="BASE_IMAGE=tmp/azure-devops-agent:base"

echo "[info] Invoking bake (targets: ${TARGETS[*]:-default})"
if [ ${#TARGETS[@]} -eq 0 ]; then
    docker buildx bake -f docker-bake.hcl --set "${SET_ARGS}"
else
    docker buildx bake -f docker-bake.hcl "${TARGETS[@]}" --set "${SET_ARGS}"
fi

echo "[success] Bake completed. Images loaded locally (single-arch)."
echo "To enable multi-arch and push: docker buildx bake -f docker-bake.hcl --set *.platforms=linux/amd64,linux/arm64 --set PUSH_GHCR=true REGISTRY=${REGISTRY} IMAGE_NAME=${REGISTRY}/azure-devops-agent"