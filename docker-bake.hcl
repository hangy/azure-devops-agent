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

variable "BASE_IMAGE" {
  # Base image reference passed in (built separately). For local dev you can leave default and build base in cache.
  default = "agent-base-image:latest"
}

group "default" {
  targets = ["dotnet", "java", "android", "flutter"]
}

target "common" {
  context = "."
  dockerfile = "Dockerfile"
  platforms = PLATFORMS
  args = {
    ARG_UBUNTU_BASE_IMAGE = BASE_IMAGE
  }
  cache-from = ["type=gha"]
  cache-to = ["type=gha,mode=max"]
}

target "dotnet" {
  inherits = ["common"]
  target = "agent-dotnet"
  tags = PUSH_GHCR ? ["${REGISTRY}/${IMAGE_NAME}:main-dotnet"] : []
  output = PUSH_GHCR ? ["type=image,push-by-digest=true,name-canonical=true,push=true"] : ["type=docker"]
}

target "java" {
  inherits = ["common"]
  target = "agent-java"
  tags = PUSH_GHCR ? ["${REGISTRY}/${IMAGE_NAME}:main-java"] : []
  output = PUSH_GHCR ? ["type=image,push-by-digest=true,name-canonical=true,push=true"] : ["type=docker"]
}

target "android" {
  inherits = ["common"]
  target = "agent-android"
  tags = PUSH_GHCR ? ["${REGISTRY}/${IMAGE_NAME}:main-android"] : []
  output = PUSH_GHCR ? ["type=image,push-by-digest=true,name-canonical=true,push=true"] : ["type=docker"]
}

target "flutter" {
  inherits = ["common"]
  target = "agent-flutter"
  tags = PUSH_GHCR ? ["${REGISTRY}/${IMAGE_NAME}:main-flutter"] : []
  output = PUSH_GHCR ? ["type=image,push-by-digest=true,name-canonical=true,push=true"] : ["type=docker"]
}
