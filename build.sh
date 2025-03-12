#!/bin/bash

set -euo pipefail
export REGISTRY="${REGISTRY:-agent}"
TAG="${TAG:-latest}"

export UBUNTU_BASE_IMAGE="${UBUNTU_BASE_IMAGE:-ubuntu}"
export UBUNTU_BASE_IMAGE_TAG="${UBUNTU_BASE_IMAGE_TAG:-20.04}"
export TARGETARCH="${TARGETARCH:-linux-x64}"
export VSTS_AGENT_VERSION="${VSTS_AGENT_VERSION:-4.252.0}"

pushd azure-devops-agent-on-kubernetes
REGISTRY=tmp TAG=base ./local-build.sh
popd

docker build ./src \
    --build-arg ARG_UBUNTU_BASE_IMAGE=tmp/azure-devops-agent \
    --build-arg ARG_UBUNTU_BASE_IMAGE_TAG=base \
    -f ./Dockerfile \
    -t ${REGISTRY}/azure-devops-agent:${TAG} \
    --progress=plain \
    "$@"