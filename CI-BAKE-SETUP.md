# Docker Bake CI Setup

## Overview

This setup uses `docker buildx bake` to simplify the CI pipeline and leverage BuildKit's parallelization capabilities.

## Files

- **`docker-bake.hcl`**: Declarative build configuration defining all four image targets
- **`.github/workflows/ci-bake.yaml`**: Simplified workflow using bake

## How It Works

### Build Process

1. **Base image** is built once and pushed to local registry
2. **`docker buildx bake`** reads `docker-bake.hcl` and:
   - Analyzes the Dockerfile dependency graph
   - Builds `agent-dotnet` and `agent-java` **in parallel** (both depend only on `agent`)
   - Builds `agent-android` after `agent-java` completes
   - Builds `agent-flutter` after `agent-android` completes
   - All targets share BuildKit's internal cache

### Multi-Architecture Support

Currently builds for `linux/amd64` only. To enable arm64:

**In `docker-bake.hcl`**:
```hcl
variable "PLATFORMS" {
  default = ["linux/amd64", "linux/arm64"]
}
```

**In `ci-bake.yaml`** (base image build):
```yaml
platforms: linux/amd64,linux/arm64
```

When multiple platforms are specified:
- Bake automatically creates multi-arch manifest lists
- Each target pushes by digest for each architecture
- Final step creates tagged manifest lists combining all architectures

### Test vs Production

**Non-main branches (PRs, test branches)**:
Local (non-main branch) builds now load images directly into your Docker daemon without requiring a local registry.

## Local Development Usage

You can build any target locally without pushing:

1. Ensure Buildx is available (Docker Desktop or `docker buildx create --use`).
2. Build base stage (optional if cache already populated):
   docker build --target agent -t agent-base-image:latest .
3. Invoke bake for all targets (no push):
   docker buildx bake -f docker-bake.hcl
4. Or only specific targets:
   docker buildx bake -f docker-bake.hcl dotnet java

Resulting images will appear locally as dangling (no tag) unless you add a tag via `docker tag <image_id> my-custom:tag`. On main branch CI, tags are applied and pushed automatically.

## Multi-Architecture Builds

By default the bake file uses only `linux/amd64` so local `type=docker` outputs can load successfully. The Docker exporter cannot load a multi-platform manifest list directly; attempting multi-arch with `type=docker` yields:

"docker exporter does not currently support exporting manifest lists"

Enable multi-arch (amd64 + arm64) only when you intend to push to a registry or export to an OCI tar:

```
docker buildx bake -f docker-bake.hcl --set *.platforms=linux/amd64,linux/arm64 --set dotnet.output=type=image --set java.output=type=image --set android.output=type=image --set flutter.output=type=image
```

Or for all targets when pushing (GHCR scenario) just rely on the workflow `PUSH_GHCR=true` and add:

```
--set *.platforms=linux/amd64,linux/arm64
```

Preconditions:
* QEMU emulation set up (`docker/setup-qemu-action` in CI or `docker run --privileged --rm tonistiigi/binfmt --install all` locally).
* Avoid architecture-specific assumptions beyond those already mapped (Compose, .NET, Kustomize use internal arch translation). Review any new tooling you add.

## Tagging Locally (Optional)

If you want stable local tags without pushing:

for TARGET in agent dotnet java android; do
  IMAGE_ID=$(docker images --filter 'label=org.opencontainers.image.title=Azure DevOps Agent (multi-capability)' --filter "reference=<none>" -q | head -n1)
  docker tag "$IMAGE_ID" "agent-${TARGET}:dev"
done

Or build a single target with a tag directly:

docker buildx build --target agent-java -t agent-java:dev .

## Updating Versions

Pass updated versions using `--set` flags in bake or edit Dockerfile ARG defaults. Example:

docker buildx bake -f docker-bake.hcl --set common.args.DOTNET_VERSION=9.0.201 dotnet

## Clean Up

Remove intermediate images and dangling layers:

docker image prune -f
docker buildx prune -f
- Uses GitHub Actions cache
- **No GHCR push**

**Main branch only**:
- Builds all targets
- Pushes to GHCR by digest
- Creates manifest lists with proper tags (`:main-{target}`, `:latest-{target}`, `:sha-{target}`)

## Advantages Over Previous Approach

| Aspect | Old (multi-job) | New (bake) |
|--------|----------------|------------|
| **Jobs** | 5 (base, dotnet-java, android, flutter, merge) | 1 |
| **Artifacts** | Large image tarballs transferred | None (BuildKit internal cache) |
| **Parallelization** | GitHub Actions matrix | BuildKit native |
| **Workflow lines** | ~500 | ~100 |
| **Layer reuse** | Via artifacts/registry | BuildKit automatic |
| **Complexity** | High (digest management, artifact orchestration) | Low (declarative config) |

## Local Testing

```bash
# Build all targets locally
docker buildx bake

# Build specific target
docker buildx bake dotnet

# Build and push to GHCR (main branch equivalent)
docker buildx bake --set PUSH_GHCR=true --push

# Override platforms
docker buildx bake --set '*.platforms=linux/amd64,linux/arm64'
```

## How BuildKit Parallelizes

When you run `docker buildx bake`, BuildKit:

1. Parses the Dockerfile and bake config
2. Builds a dependency graph of all stages
3. Identifies stages that can be built in parallel:
   ```
   agent (base)
   ├── agent-dotnet (parallel)
   └── agent-java (parallel)
       └── agent-android
           └── agent-flutter
   ```
4. Builds independent stages simultaneously
5. Shares layers across all builds via internal cache

## Extending for More Targets

To add a new target (e.g., `agent-python`):

1. Add stage to `Dockerfile`
2. Add target block to `docker-bake.hcl`:
   ```hcl
   target "python" {
     inherits = ["common"]
     target = "agent-python"
     tags = [
  PUSH_GHCR ? "${REGISTRY}/${IMAGE_NAME}:main-python" : []
     ]
     output = PUSH_GHCR ? ["type=image,name=${REGISTRY}/${IMAGE_NAME},push-by-digest=true,name-canonical=true,push=true"] : ["type=image,push=true"]
   }
   ```
3. Add to `group "default"` in bake file
4. Add to manifest creation loop in workflow

No changes needed to job orchestration!
