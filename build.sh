#!/bin/bash

set -euo pipefail

# High-level: directly bake base + capability targets; base is now an internal bake target (pattern B).

REGISTRY="${REGISTRY:-agent}"          # Used only if you push manually with overrides
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! docker buildx inspect >/dev/null 2>&1; then
    echo "[info] No default buildx builder; creating one"
    docker buildx create --use >/dev/null
fi

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
    echo "[info] Baking default target group (includes base-dependent capability images)"
    docker buildx bake -f docker-bake.hcl
else
    echo "[info] Baking selected targets: ${TARGETS[*]}" 
    docker buildx bake -f docker-bake.hcl "${TARGETS[@]}"
fi

echo "[success] Bake completed. Images loaded locally (single-arch)."
echo "To enable multi-arch & push: docker buildx bake -f docker-bake.hcl --set *.platforms=linux/amd64,linux/arm64 --set PUSH_GHCR=true REGISTRY=${REGISTRY} IMAGE_NAME=${REGISTRY}/azure-devops-agent"