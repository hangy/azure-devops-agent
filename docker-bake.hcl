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
variable "SYFT_IMAGE" {
  default = "ghcr.io/anchore/syft:v1.36.0-nonroot"
}
group "default" {
  targets = ["dotnet", "java", "android", "flutter"]
}

# Internal base image target. This produces the richer agent-base-image.
target "base" {
  # Use submodule root as dockerfile location and include src file via COPY by adjusting build args.
  context = "azure-devops-agent-on-kubernetes/src"
  dockerfile = "../Dockerfile"
  platforms = PLATFORMS
  # Internal base image does not need canonical digest-only push; build graph consumers use target:base.
  output = PUSH_GHCR ? ["type=image,push=true"] : ["type=docker"]
}

target "common" {
  context = "."
  dockerfile = "Dockerfile"
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

target "dotnet" {
  inherits = ["common"]
  target = "agent-dotnet"
  tags = PUSH_GHCR ? ["${REGISTRY}/${IMAGE_NAME}:main-dotnet"] : []
  # Push by tag; digest will still be available for signing/inspection. push-by-digest removed due to GHCR incompatibility with tagged digest-only push.
  output = PUSH_GHCR ? ["type=image,push=true"] : ["type=docker"]
  # Produce provenance and SBOM attestations (SBOM requires type=sbom entry rather than legacy sbom directive for cosign download).
  attest = PUSH_GHCR ? [
    "type=provenance,mode=max",
    "type=sbom,generator=${SYFT_IMAGE}"
  ] : []
}

target "java" {
  inherits = ["common"]
  target = "agent-java"
  tags = PUSH_GHCR ? ["${REGISTRY}/${IMAGE_NAME}:main-java"] : []
  output = PUSH_GHCR ? ["type=image,push=true"] : ["type=docker"]
  attest = PUSH_GHCR ? [
    "type=provenance,mode=max",
    "type=sbom,generator=${SYFT_IMAGE}"
  ] : []
}

target "android" {
  inherits = ["common"]
  target = "agent-android"
  tags = PUSH_GHCR ? ["${REGISTRY}/${IMAGE_NAME}:main-android"] : []
  output = PUSH_GHCR ? ["type=image,push=true"] : ["type=docker"]
  attest = PUSH_GHCR ? [
    "type=provenance,mode=max",
    "type=sbom,generator=${SYFT_IMAGE}"
  ] : []
}

target "flutter" {
  inherits = ["common"]
  target = "agent-flutter"
  tags = PUSH_GHCR ? ["${REGISTRY}/${IMAGE_NAME}:main-flutter"] : []
  output = PUSH_GHCR ? ["type=image,push=true"] : ["type=docker"]
  attest = PUSH_GHCR ? [
    "type=provenance,mode=max",
    "type=sbom,generator=${SYFT_IMAGE}"
  ] : []
}
