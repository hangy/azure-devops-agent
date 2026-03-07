# syntax=docker/dockerfile:1
ARG ARG_UBUNTU_BASE_IMAGE="agent-base-image"
ARG VCS_REF
ARG BUILD_DATE
ARG VSTS_AGENT_VERSION
ARG USER_NAME=ubuntu

FROM ${ARG_UBUNTU_BASE_IMAGE} AS agent

# Use bash with strict options for all subsequent RUN commands in this stage
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Re-declare build metadata args for this stage (required for some linters)
ARG VCS_REF
ARG BUILD_DATE
ARG VSTS_AGENT_VERSION
ARG COMPOSE_SHA256=""
ARG APT_FLAGS="-y --no-install-recommends"
ARG USER_NAME

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
ARG COMPOSE_VERSION=5.0.2
ARG COMPOSE_SHA256_AMD64=2d880f723d3da7c779c54fdaea91a842fca8af55d1397f1ed8d7cbab3dd7af67
ARG COMPOSE_SHA256_ARM64=ac7810e0cd56a5b58576688196fafa843e07e8241fb91018a736d549ea20a3f3
RUN COMPOSE_ARCH="${TARGETARCH}"; \
        case "${TARGETARCH}" in \
            amd64) COMPOSE_ARCH="x86_64"; COMPOSE_SHA256="${COMPOSE_SHA256_AMD64}" ;; \
            arm64) COMPOSE_ARCH="aarch64"; COMPOSE_SHA256="${COMPOSE_SHA256_ARM64}" ;; \
        esac; \
        curl -fsSL "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-${COMPOSE_ARCH}" -o /usr/local/bin/docker-compose; \
        if [ -n "${COMPOSE_SHA256}" ]; then \
             echo "${COMPOSE_SHA256}  /usr/local/bin/docker-compose" | sha256sum -c -; \
        fi; \
        chmod +x /usr/local/bin/docker-compose; \
        /usr/local/bin/docker-compose --version

# Install Kustomize
ARG KUSTOMIZE_VERSION=5.8.0
ARG KUSTOMIZE_SHA256_AMD64=4dfa8307358dd9284aa4d2b1d5596766a65b93433e8fa3f9f74498941f01c5ef
ARG KUSTOMIZE_SHA256_ARM64=a4f48b4c3d4ca97d748943e19169de85a2e86e80bcc09558603e2aa66fb15ce1
RUN KUSTOMIZE_ARCH="${TARGETARCH}"; \
    case "${TARGETARCH}" in \
        amd64) KUSTOMIZE_ARCH="amd64"; KUSTOMIZE_SHA256="${KUSTOMIZE_SHA256_AMD64}" ;; \
        arm64) KUSTOMIZE_ARCH="arm64"; KUSTOMIZE_SHA256="${KUSTOMIZE_SHA256_ARM64}" ;; \
    esac; \
    curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_${KUSTOMIZE_ARCH}.tar.gz" -o kustomize.tar.gz; \
    if [ -n "${KUSTOMIZE_SHA256}" ]; then \
        echo "${KUSTOMIZE_SHA256}  kustomize.tar.gz" | sha256sum -c -; \
    fi; \
    tar -xzf kustomize.tar.gz -C /usr/local/bin; \
    rm kustomize.tar.gz; \
    chmod +x /usr/local/bin/kustomize; \
    kustomize version

USER ${USER_NAME}
ENTRYPOINT ["./add-certs-and-start.sh"]

FROM agent AS agent-dotnet

# Re-apply bash strict shell in new stage
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG USER_NAME

# Add .NET SDK
ARG DOTNET_VERSION=10.0.103
ARG DOTNET_SHA512_AMD64=bab94f13c57b2ac821d4924fe66084be9b44c41761ff7ff64522c8f7aba345659d31258401dcec31cc3cf6ccae1d012623075aca1c9b9165bcfe5ba9abda1c0c
ARG DOTNET_SHA512_ARM64=ab45b6baeae956e4465151787d8b8113b66679ed55da1e72c57e99aa5ab8f42471e80dc8a5fd22c31df74e60446a3b252d2900658cefc9506fcb0da7e2831e21
RUN DOTNET_ARCH="${TARGETARCH}"; \
    case "${TARGETARCH}" in \
        amd64) DOTNET_ARCH="x64"; DOTNET_SHA512="${DOTNET_SHA512_AMD64}" ;; \
        arm64) DOTNET_ARCH="arm64"; DOTNET_SHA512="${DOTNET_SHA512_ARM64}" ;; \
    esac; \
    curl -fsSL "https://builds.dotnet.microsoft.com/dotnet/Sdk/${DOTNET_VERSION}/dotnet-sdk-${DOTNET_VERSION}-linux-${DOTNET_ARCH}.tar.gz" -o dotnet.tar.gz; \
    if [ -n "${DOTNET_SHA512}" ]; then \
        echo "${DOTNET_SHA512}  dotnet.tar.gz" | sha512sum -c -; \
    fi; \
    mkdir -p /home/${USER_NAME}/.dotnet; \
    tar -xzf dotnet.tar.gz -C /home/${USER_NAME}/.dotnet; \
    rm dotnet.tar.gz

ENV DOTNET_ROOT="/home/${USER_NAME}/.dotnet"
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
ENV DOTNET_NOLOGO=1
ENV PATH="${DOTNET_ROOT}:${PATH}"

FROM agent AS agent-java

# Re-apply bash strict shell in new stage
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG USER_NAME

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

USER ${USER_NAME}

FROM agent-java AS agent-android

# Re-apply bash strict shell in new stage
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG USER_NAME

# Android SDK
ARG ANDROID_COMPILE_SDK=36
ARG ANDROID_BUILD_TOOLS=36.0.0
ARG ANDROID_SDK_TOOLS=13114758
ARG NDK_VERSION=29.0.14206865
ARG CMAKE_VERSION=4.1.2
ARG ANDROID_SDK_ZIP_SHA256="7ec965280a073311c339e571cd5de778b9975026cfcbe79f2b1cdcb1e15317ee"

RUN curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_TOOLS}_latest.zip" -o android-sdk.zip && \
    if [ -n "${ANDROID_SDK_ZIP_SHA256}" ]; then echo "${ANDROID_SDK_ZIP_SHA256}  android-sdk.zip" | sha256sum -c -; fi && \
    mkdir -p /home/${USER_NAME}/android-sdk-linux/cmdline-tools && \
    unzip -d /home/${USER_NAME}/android-sdk-linux/cmdline-tools android-sdk.zip && \
    rm android-sdk.zip && \
    mv /home/${USER_NAME}/android-sdk-linux/cmdline-tools/cmdline-tools /home/${USER_NAME}/android-sdk-linux/cmdline-tools/latest && \
    echo y | /home/${USER_NAME}/android-sdk-linux/cmdline-tools/latest/bin/sdkmanager "platforms;android-${ANDROID_COMPILE_SDK}" >/dev/null && \
    echo y | /home/${USER_NAME}/android-sdk-linux/cmdline-tools/latest/bin/sdkmanager "platform-tools" >/dev/null && \
    echo y | /home/${USER_NAME}/android-sdk-linux/cmdline-tools/latest/bin/sdkmanager "build-tools;${ANDROID_BUILD_TOOLS}" >/dev/null && \
    echo y | /home/${USER_NAME}/android-sdk-linux/cmdline-tools/latest/bin/sdkmanager --install "ndk;${NDK_VERSION}" >/dev/null && \
    echo y | /home/${USER_NAME}/android-sdk-linux/cmdline-tools/latest/bin/sdkmanager --install "cmake;${CMAKE_VERSION}" >/dev/null && \
    (yes || true) | /home/${USER_NAME}/android-sdk-linux/cmdline-tools/latest/bin/sdkmanager --licenses

ENV ANDROID_SDK_ROOT="/home/${USER_NAME}/android-sdk-linux"
ENV ANDROID_HOME="/home/${USER_NAME}/android-sdk-linux"
ENV ANDROID_COMPILE_SDK="${ANDROID_COMPILE_SDK}" ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS}" ANDROID_SDK_TOOLS="${ANDROID_SDK_TOOLS}" NDK_VERSION="${NDK_VERSION}" CMAKE_VERSION="${CMAKE_VERSION}"

ENV ANDROID_NDK="$ANDROID_SDK_ROOT/ndk/${NDK_VERSION}"
ENV PATH="${PATH}:$ANDROID_HOME/platform-tools"
ENV PATH="${PATH}:$ANDROID_SDK_ROOT/build-tools/${ANDROID_BUILD_TOOLS}:$ANDROID_NDK"

