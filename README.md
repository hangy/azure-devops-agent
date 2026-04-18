# Azure DevOps Agent Images (custom fork)

This repository builds self-hosted Azure DevOps agent images with multiple toolchains useful for CI pipelines. The images are
produced from the base and variant Dockerfiles in this repository and via the bake configuration in `docker-bake.hcl`.
 
Note: The `azure-devops-agent-on-kubernetes` base image and Helm chart are based on the work of btungut — see the original project by Burak TUNGUT: [btungut/azure-devops-agent-on-kubernetes](https://github.com/btungut/azure-devops-agent-on-kubernetes).

Quick summary
- Base image: built from [azure-devops-agent-on-kubernetes/Dockerfile](azure-devops-agent-on-kubernetes/Dockerfile) and extended by [Dockerfile](Dockerfile).
- Build variants and targets are defined in [docker-bake.hcl](docker-bake.hcl) and used by the CI workflow [/.github/workflows/ci.yaml](.github/workflows/ci.yaml).

Available image variants
- `plain` — minimal agent image
- `dotnet` — agent + .NET SDK
- `java` — agent + multiple JDKs
- `android` — Java + Android SDK and related Android toolchain

Included toolchains by variant (major versions only)

- `plain` (minimal agent)
  - Azure DevOps agent: 4.x
  - cosign: 3.x
  - docker-compose: 5.x
  - kustomize: 5.x
  - buildkit: 0.x
  - kubectl: 1.x
  - helm: 4.x
  - yq: 4.x
  - PowerShell (pwsh): 7.x

- `dotnet` (plain + .NET)
  - .NET SDK: 10.x

- `java` (plain + Java toolchain)
  - Java JDKs: 8, 17, 21, 25
  - common Java build tools (Maven, Gradle, Ant)

- `android` (java + Android SDK)
  - Android SDK / cmdline tools and platform: API 36
  - Build Tools: 36
  - NDK: 29
  - CMake: 4.x

Notes on exact versions
- Exact, pinned versions (minor/patch) are kept in the JSON files under `src/dependencies/` and `azure-devops-agent-on-kubernetes/src/dependencies/`. For example: [src/dependencies/dotnet-sdk.json](src/dependencies/dotnet-sdk.json), [src/dependencies/cosign.json](src/dependencies/cosign.json), [src/dependencies/android-sdk.json](src/dependencies/android-sdk.json), and [azure-devops-agent-on-kubernetes/src/dependencies/agent.json](azure-devops-agent-on-kubernetes/src/dependencies/agent.json).

Build & CI
- Local build (uses Docker Buildx bake):

```bash
./build.sh
```

- CI: the GitHub Actions workflow [/.github/workflows/ci.yaml](.github/workflows/ci.yaml) builds images, optionally runs Trivy scans, extracts SBOMs, and signs images with Cosign when pushing from the `main` branch. Tags produced by the bake file include `main-plain`, `main-dotnet`, `main-java`, and `main-android` when `PUSH_GHCR` is enabled.

Flutter
- There is no Flutter layer baked into the images. Instead we recommend installing Flutter at pipeline runtime using FVM (faster caching and avoids image bloat). Example pipeline step (install FVM, then install a Flutter major version):

```yaml
- script: |
    curl -L https://github.com/fvm/fvm/releases/latest/download/fvm-linux-x64.tar.gz | tar xz -C /usr/local/bin
    fvm --version
    # install desired Flutter major release (example: 3)
    fvm install 3
    fvm flutter --version
  displayName: Install FVM and Flutter
```

Where to look / how to update
- Change pinned tool versions in the dependency JSON files under `src/dependencies/` (and in `azure-devops-agent-on-kubernetes/src/dependencies/` for the base image). After updating those files, the Dockerfile stages and CI build will pick up the new downloads.

Contributing
- Please open a PR if you want to update pinned versions or add new tools. Keep only major version recommendations in this README — exact pins belong in the `dependencies` JSON files.

License: MIT
