#!/bin/bash

set -euo pipefail

# High-level: build base image with local-build.sh, then bake capability targets using that image via BASE_IMAGE variable.

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

if ! docker buildx inspect >/dev/null 2>&1; then
    echo "[info] No default buildx builder; creating one"
    docker buildx create --use >/dev/null
fi

# Allow specifying targets as script args; default builds all (group default)
TARGETS=("$@")
BASE_IMAGE_REF="tmp/azure-devops-agent:base"

echo "[info] Invoking bake (targets: ${TARGETS[*]:-default}) using BASE_IMAGE='${BASE_IMAGE_REF}'"
if [ ${#TARGETS[@]} -eq 0 ]; then
    BASE_IMAGE="${BASE_IMAGE_REF}" docker buildx bake -f docker-bake.hcl
else
    BASE_IMAGE="${BASE_IMAGE_REF}" docker buildx bake -f docker-bake.hcl "${TARGETS[@]}"
fi

echo "[success] Bake completed. Images loaded locally (single-arch)."
echo "To enable multi-arch and push: BASE_IMAGE='${BASE_IMAGE_REF}' docker buildx bake -f docker-bake.hcl --set *.platforms=linux/amd64,linux/arm64 --set PUSH_GHCR=true REGISTRY=${REGISTRY} IMAGE_NAME=${REGISTRY}/azure-devops-agent"