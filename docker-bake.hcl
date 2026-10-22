variable "REGISTRY" {
  default = "ghcr.io"
}

variable "IMAGE_NAME" {
  default = "hangy/azure-devops-agent"
}

variable "PLATFORMS" {
  # Default to single platform so local (type=docker) loads succeed.
  # Multi-platform + type=docker causes: "docker exporter does not currently support exporting manifest lists".
  # Enable multi-arch explicitly via: docker buildx bake -f docker-bake.hcl --set *.platforms=linux/amd64,linux/arm64
  default = ["linux/amd64"]
}

variable "PUSH_GHCR" {
  default = false
}

variable "UBUNTU_SNAPSHOT" {
  # Empty (default) means: use the submodule Dockerfile's ARG_UBUNTU_SNAPSHOT
  # default. Set to a YYYYMMDDTHHMMSSZ timestamp to build the base image
  # against a different snapshot; the agent stages on top inherit it
  # automatically, e.g.:
  #   UBUNTU_SNAPSHOT=20261101T000000Z docker buildx bake -f docker-bake.hcl
  default = ""
}

group "default" {
    targets = ["plain", "dotnet", "java", "android"]
}

# Internal base image target. This produces the richer agent-base-image.
target "base" {
  # Use submodule root as dockerfile location and include src file via COPY by adjusting build args.
  context = "azure-devops-agent-on-kubernetes/src"
  dockerfile = "../Dockerfile"
  platforms = PLATFORMS
  # Only pass the snapshot when explicitly set; otherwise the submodule
  # Dockerfile's own ARG_UBUNTU_SNAPSHOT default applies.
  args = UBUNTU_SNAPSHOT != "" ? { ARG_UBUNTU_SNAPSHOT = UBUNTU_SNAPSHOT } : {}
  # Internal base image does not need canonical digest-only push; build graph consumers use target:base.
  output = PUSH_GHCR ? ["type=image,push=true"] : ["type=docker"]
}

target "common" {
  context = "src"
  dockerfile = "../Dockerfile"
  platforms = PLATFORMS
  args = {
    ARG_UBUNTU_BASE_IMAGE = "agent-base-image"
  }
  contexts = {
    agent-base-image = "target:base"
  }
  cache-from = ["type=gha"]
  cache-to = ["type=gha,mode=max"]
}

target "plain" {
  inherits = ["common"]
  target = "agent"
  tags = PUSH_GHCR ? ["${REGISTRY}/${IMAGE_NAME}:main-plain"] : []
  # Push by tag; digest will still be available for signing/inspection. push-by-digest removed due to GHCR incompatibility with tagged digest-only push.
  output = PUSH_GHCR ? ["type=image,push=true"] : ["type=docker"]
  attest = PUSH_GHCR ? ["type=provenance,mode=max"] : []
  sbom = true
}

target "dotnet" {
  inherits = ["common"]
  target = "agent-dotnet"
  tags = PUSH_GHCR ? ["${REGISTRY}/${IMAGE_NAME}:main-dotnet"] : []
  # Push by tag; digest will still be available for signing/inspection. push-by-digest removed due to GHCR incompatibility with tagged digest-only push.
  output = PUSH_GHCR ? ["type=image,push=true"] : ["type=docker"]
  attest = PUSH_GHCR ? ["type=provenance,mode=max"] : []
  sbom = true
}

target "java" {
  inherits = ["common"]
  target = "agent-java"
  tags = PUSH_GHCR ? ["${REGISTRY}/${IMAGE_NAME}:main-java"] : []
  output = PUSH_GHCR ? ["type=image,push=true"] : ["type=docker"]
  attest = PUSH_GHCR ? ["type=provenance,mode=max"] : []
  sbom = true
}

target "android" {
  inherits = ["java"]
  target = "agent-android"
  tags = PUSH_GHCR ? ["${REGISTRY}/${IMAGE_NAME}:main-android"] : []
  output = PUSH_GHCR ? ["type=image,push=true"] : ["type=docker"]
  attest = PUSH_GHCR ? ["type=provenance,mode=max"] : []
  sbom = true
}
