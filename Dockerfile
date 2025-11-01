# syntax=docker/dockerfile:1
ARG ARG_UBUNTU_BASE_IMAGE="agent-base-image"
ARG VCS_REF
ARG BUILD_DATE
ARG VSTS_AGENT_VERSION

FROM ${ARG_UBUNTU_BASE_IMAGE} AS agent

# Use bash with strict options for all subsequent RUN commands in this stage
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Re-declare build metadata args for this stage (required for some linters)
ARG VCS_REF
ARG BUILD_DATE
ARG VSTS_AGENT_VERSION
ARG COMPOSE_SHA256=""
ARG APT_FLAGS="-y --no-install-recommends"

LABEL org.opencontainers.image.source="https://github.com/hangy/azure-devops-agent" \
    org.opencontainers.image.revision="${VCS_REF}" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.version="${VSTS_AGENT_VERSION}" \
    org.opencontainers.image.title="Azure DevOps Agent (multi-capability)" \
    org.opencontainers.image.description="Azure DevOps self-hosted agent with Docker, Kustomize, .NET, Java, Android, and Flutter toolchains." \
    org.opencontainers.image.licenses="MIT"

USER root

WORKDIR /azp
COPY ./*.sh .

# Install common build tools
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && \
    apt-get install ${APT_FLAGS} ca-certificates curl default-jre-headless git unzip xz-utils zip

# Install Compose
ARG TARGETARCH
RUN COMPOSE_ARCH="${TARGETARCH}"; \
        case "${TARGETARCH}" in \
            amd64) COMPOSE_ARCH="x86_64" ;; \
            arm64) COMPOSE_ARCH="aarch64" ;; \
        esac; \
        curl -fsSL "https://github.com/docker/compose/releases/download/v2.40.2/docker-compose-linux-${COMPOSE_ARCH}" -o /usr/local/bin/docker-compose; \
        if [ -n "${COMPOSE_SHA256}" ]; then \
             echo "${COMPOSE_SHA256}  /usr/local/bin/docker-compose" | sha256sum -c -; \
        fi; \
        chmod +x /usr/local/bin/docker-compose; \
        /usr/local/bin/docker-compose --version

# Install Kustomize
ARG KUSTOMIZE_VERSION=5.7.1
ARG KUSTOMIZE_SHA256="4704f8b47582c1c52bf76a50b37178f7f7de17f892713794a8bf44b01b50e0ce"
RUN KUSTOMIZE_ARCH="${TARGETARCH}"; \
    case "${TARGETARCH}" in \
        amd64) KUSTOMIZE_ARCH="amd64" ;; \
        arm64) KUSTOMIZE_ARCH="arm64" ;; \
    esac; \
    curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_${KUSTOMIZE_ARCH}.tar.gz" -o kustomize.tar.gz; \
    if [ -n "${KUSTOMIZE_SHA256}" ]; then \
        echo "${KUSTOMIZE_SHA256}  kustomize.tar.gz" | sha256sum -c -; \
    fi; \
    tar -xzf kustomize.tar.gz -C /usr/local/bin; \
    rm kustomize.tar.gz; \
    chmod +x /usr/local/bin/kustomize; \
    kustomize version

USER azdouser
ENTRYPOINT ["./add-certs-and-start.sh"]

FROM agent AS agent-dotnet

# Re-apply bash strict shell in new stage
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Add .NET SDK
ARG DOTNET_VERSION=10.0.100-rc.2.25502.107
ARG DOTNET_SHA512="1200ff33d7c2a834499590e05f46c065d0f7dc1f7520f35403b5d4fc1fb00bddfb7c4aae230280e8dc6890fe5fc5ca738dea4789056614ed02a84d1e86d068e9"
RUN DOTNET_ARCH="${TARGETARCH}"; \
    case "${TARGETARCH}" in \
        amd64) DOTNET_ARCH="x64" ;; \
        arm64) DOTNET_ARCH="arm64" ;; \
    esac; \
    curl -fsSL "https://dotnetcli.azureedge.net/dotnet/Sdk/${DOTNET_VERSION}/dotnet-sdk-${DOTNET_VERSION}-linux-${DOTNET_ARCH}.tar.gz" -o dotnet.tar.gz; \
    if [ -n "${DOTNET_SHA512}" ]; then \
        echo "${DOTNET_SHA512}  dotnet.tar.gz" | sha512sum -c -; \
    fi; \
    mkdir -p /home/azdouser/.dotnet; \
    tar -xzf dotnet.tar.gz -C /home/azdouser/.dotnet; \
    rm dotnet.tar.gz

ENV DOTNET_ROOT="/home/azdouser/.dotnet"
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
ENV DOTNET_NOLOGO=1
ENV PATH="${DOTNET_ROOT}:${PATH}"

FROM agent AS agent-java

# Re-apply bash strict shell in new stage
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

USER root

# Add Java
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && \
    apt-get install ${APT_FLAGS} \
            ant \
            gradle \
            maven \
            openjdk-17-jdk-headless \
            openjdk-21-jdk-headless \
            openjdk-8-jdk-headless && \
        update-java-alternatives -a || true

ENV JAVA_HOME_8_X64=/usr/lib/jvm/java-8-openjdk-amd64
ENV JAVA_HOME_17_X64=/usr/lib/jvm/java-17-openjdk-amd64
ENV JAVA_HOME_21_X64=/usr/lib/jvm/java-21-openjdk-amd64
ENV JAVA_HOME=${JAVA_HOME_21_X64}
ENV ANT_HOME=/usr/share/ant
ENV GRADLE_HOME=/usr/share/gradle
ENV M2_HOME=/usr/share/maven
ENV PATH="${ANT_HOME}/bin:${GRADLE_HOME}/bin:${M2_HOME}/bin:${PATH}"

USER azdouser

FROM agent-java AS agent-android

# Re-apply bash strict shell in new stage
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Android SDK
ARG ANDROID_COMPILE_SDK=36
ARG ANDROID_BUILD_TOOLS=36.0.0
ARG ANDROID_SDK_TOOLS=13114758
ARG NDK_VERSION=29.0.14206865
ARG CMAKE_VERSION=4.1.2
ARG ANDROID_SDK_ZIP_SHA256="7ec965280a073311c339e571cd5de778b9975026cfcbe79f2b1cdcb1e15317ee"

RUN curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_TOOLS}_latest.zip" -o android-sdk.zip && \
    if [ -n "${ANDROID_SDK_ZIP_SHA256}" ]; then echo "${ANDROID_SDK_ZIP_SHA256}  android-sdk.zip" | sha256sum -c -; fi && \
    mkdir -p /home/azdouser/android-sdk-linux/cmdline-tools && \
    unzip -d /home/azdouser/android-sdk-linux/cmdline-tools android-sdk.zip && \
    rm android-sdk.zip && \
    mv /home/azdouser/android-sdk-linux/cmdline-tools/cmdline-tools /home/azdouser/android-sdk-linux/cmdline-tools/latest && \
    echo y | /home/azdouser/android-sdk-linux/cmdline-tools/latest/bin/sdkmanager "platforms;android-${ANDROID_COMPILE_SDK}" >/dev/null && \
    echo y | /home/azdouser/android-sdk-linux/cmdline-tools/latest/bin/sdkmanager "platform-tools" >/dev/null && \
    echo y | /home/azdouser/android-sdk-linux/cmdline-tools/latest/bin/sdkmanager "build-tools;${ANDROID_BUILD_TOOLS}" >/dev/null && \
    echo y | /home/azdouser/android-sdk-linux/cmdline-tools/latest/bin/sdkmanager --install "ndk;${NDK_VERSION}" >/dev/null && \
    echo y | /home/azdouser/android-sdk-linux/cmdline-tools/latest/bin/sdkmanager --install "cmake;${CMAKE_VERSION}" >/dev/null && \
    (yes || true) | /home/azdouser/android-sdk-linux/cmdline-tools/latest/bin/sdkmanager --licenses

ENV ANDROID_SDK_ROOT="/home/azdouser/android-sdk-linux"
ENV ANDROID_HOME="/home/azdouser/android-sdk-linux"
ENV ANDROID_COMPILE_SDK="${ANDROID_COMPILE_SDK}" ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS}" ANDROID_SDK_TOOLS="${ANDROID_SDK_TOOLS}" NDK_VERSION="${NDK_VERSION}" CMAKE_VERSION="${CMAKE_VERSION}"

ENV ANDROID_NDK="$ANDROID_SDK_ROOT/ndk/${NDK_VERSION}"
ENV PATH="${PATH}:$ANDROID_HOME/platform-tools"
ENV PATH="${PATH}:$ANDROID_SDK_ROOT/build-tools/${ANDROID_BUILD_TOOLS}:$ANDROID_NDK"

FROM agent-android AS agent-flutter

# Re-apply bash strict shell in new stage
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG FLUTTER_VERSION=3.35.7
ARG FLUTTER_TAR_SHA256="146df531f9ac6a11a918013c1a70faafc053d4811c8cb69a413fd70748d51c3d"

USER root

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && \
    apt-get install ${APT_FLAGS} \
            lib32z1 \
            libbz2-1.0:amd64 \
            libc6:amd64 \
            libglu1-mesa \
            libstdc++6:amd64

USER azdouser

RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o flutter-sdk.tar.xz && \
    if [ -n "${FLUTTER_TAR_SHA256}" ]; then echo "${FLUTTER_TAR_SHA256}  flutter-sdk.tar.xz" | sha256sum -c -; fi && \
    tar -xf flutter-sdk.tar.xz -C /home/azdouser && \
    rm flutter-sdk.tar.xz

ENV FLUTTER_HOME="/home/azdouser/flutter"
ENV PATH="${PATH}:${FLUTTER_HOME}/bin"
