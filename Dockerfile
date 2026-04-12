# syntax=docker/dockerfile:1
ARG ARG_UBUNTU_BASE_IMAGE="agent-base-image"
ARG VCS_REF
ARG BUILD_DATE
ARG VSTS_AGENT_VERSION
ARG USER_NAME=ubuntu

FROM ${ARG_UBUNTU_BASE_IMAGE} AS base

# Use bash with strict options for all subsequent RUN commands in this stage
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Re-declare build metadata args for this stage (required for some linters)
ARG VCS_REF
ARG BUILD_DATE
ARG VSTS_AGENT_VERSION
ARG APT_FLAGS="-y --no-install-recommends"
ARG USER_NAME
ARG TARGETARCH

LABEL org.opencontainers.image.source="https://github.com/hangy/azure-devops-agent" \
    org.opencontainers.image.revision="${VCS_REF}" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.version="${VSTS_AGENT_VERSION}" \
    org.opencontainers.image.title="Azure DevOps Agent (multi-capability)" \
    org.opencontainers.image.description="Azure DevOps self-hosted agent with Docker, cosign, Kustomize, .NET, Java, and Android toolchains." \
    org.opencontainers.image.licenses="MIT"

USER root

WORKDIR /azp
COPY ./*.sh .

# Install common build tools
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && \
    apt-get install ${APT_FLAGS} ca-certificates curl default-jre-headless git unzip xz-utils zip

FROM base AS download-compose
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
COPY dependencies/compose.json /tmp/compose.json
RUN COMPOSE_ARCH="${TARGETARCH}"; \
    COMPOSE_RELEASE_ARCH=$(jq -r ".download_arch[\"${COMPOSE_ARCH}\"] // \"${COMPOSE_ARCH}\"" /tmp/compose.json); \
    COMPOSE_VERSION=$(jq -r '.version' /tmp/compose.json); \
    COMPOSE_SHA256=$(jq -r ".sha256[\"${COMPOSE_ARCH}\"]" /tmp/compose.json); \
    DOWNLOAD_URL=$(jq -r '.download_url' /tmp/compose.json | sed "s/{version}/${COMPOSE_VERSION}/g" | sed "s/{arch}/${COMPOSE_RELEASE_ARCH}/g"); \
    curl -fsSL "${DOWNLOAD_URL}" -o /usr/local/bin/docker-compose; \
    echo "${COMPOSE_SHA256}  /usr/local/bin/docker-compose" | sha256sum -c -; \
    chmod +x /usr/local/bin/docker-compose; \
    /usr/local/bin/docker-compose --version

FROM base AS download-kustomize
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
COPY --link dependencies/kustomize.json /tmp/kustomize.json
RUN KUSTOMIZE_ARCH="${TARGETARCH}"; \
    KUSTOMIZE_VERSION=$(jq -r '.version' /tmp/kustomize.json); \
    KUSTOMIZE_SHA256=$(jq -r ".sha256[\"${KUSTOMIZE_ARCH}\"]" /tmp/kustomize.json); \
    DOWNLOAD_URL=$(jq -r '.download_url' /tmp/kustomize.json | sed "s/{version}/${KUSTOMIZE_VERSION}/g" | sed "s/{arch}/${KUSTOMIZE_ARCH}/g"); \
    curl -fsSL "${DOWNLOAD_URL}" -o kustomize.tar.gz; \
    echo "${KUSTOMIZE_SHA256}  kustomize.tar.gz" | sha256sum -c -; \
    tar -xzf kustomize.tar.gz -C /usr/local/bin; \
    rm kustomize.tar.gz; \
    chmod +x /usr/local/bin/kustomize; \
    kustomize version

FROM base AS download-cosign
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
COPY dependencies/cosign.json /tmp/cosign.json
RUN COSIGN_ARCH="${TARGETARCH}"; \
    COSIGN_VERSION=$(jq -r '.version' /tmp/cosign.json); \
    COSIGN_SHA256=$(jq -r ".sha256[\"${COSIGN_ARCH}\"]" /tmp/cosign.json); \
    DOWNLOAD_URL=$(jq -r '.download_url' /tmp/cosign.json | sed "s/{version}/${COSIGN_VERSION}/g" | sed "s/{arch}/${COSIGN_ARCH}/g"); \
    curl -fsSL "${DOWNLOAD_URL}" -o /usr/local/bin/cosign; \
    echo "${COSIGN_SHA256}  /usr/local/bin/cosign" | sha256sum -c -; \
    chmod +x /usr/local/bin/cosign; \
    cosign version

FROM base AS agent
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
# Add Java Runtime (Latest LTS)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && \
    apt-get install ${APT_FLAGS} \
            openjdk-25-jre-headless && \
        update-java-alternatives -a || true

COPY --from=download-compose /usr/local/bin/docker-compose /usr/local/bin/docker-compose
COPY --from=download-kustomize /usr/local/bin/kustomize /usr/local/bin/kustomize
COPY --from=download-cosign /usr/local/bin/cosign /usr/local/bin/cosign

USER ${USER_NAME}
ENTRYPOINT ["./add-certs-and-start.sh"]

FROM agent AS agent-dotnet

# Re-apply bash strict shell in new stage
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG USER_NAME

# Add .NET SDK
COPY dependencies/dotnet-sdk.json /tmp/dotnet-sdk.json
RUN DOTNET_ARCH="${TARGETARCH}"; \
    DOTNET_RELEASE_ARCH=$(jq -r ".download_arch[\"${DOTNET_ARCH}\"] // \"${DOTNET_ARCH}\"" /tmp/dotnet-sdk.json); \
    DOTNET_VERSION=$(jq -r '.version' /tmp/dotnet-sdk.json); \
    DOTNET_SHA512=$(jq -r ".sha512[\"${DOTNET_ARCH}\"]" /tmp/dotnet-sdk.json); \
    DOWNLOAD_URL=$(jq -r '.download_url' /tmp/dotnet-sdk.json | sed "s/{version}/${DOTNET_VERSION}/g" | sed "s/{arch}/${DOTNET_RELEASE_ARCH}/g"); \
    curl -fsSL "${DOWNLOAD_URL}" -o dotnet.tar.gz; \
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

# Add Java Development Kits + Common build tools (LTS)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && \
    apt-get install ${APT_FLAGS} \
            ant \
            gradle \
            maven \
            openjdk-17-jdk-headless \
            openjdk-21-jdk-headless \
            openjdk-25-jdk-headless \
            openjdk-8-jdk-headless && \
        update-java-alternatives -a || true

ENV JAVA_HOME_8_X64=/usr/lib/jvm/java-8-openjdk-amd64
ENV JAVA_HOME_17_X64=/usr/lib/jvm/java-17-openjdk-amd64
ENV JAVA_HOME_21_X64=/usr/lib/jvm/java-21-openjdk-amd64
ENV JAVA_HOME_25_X64=/usr/lib/jvm/java-25-openjdk-amd64
ENV JAVA_HOME=${JAVA_HOME_25_X64}
ENV ANT_HOME=/usr/share/ant
ENV GRADLE_HOME=/usr/share/gradle
ENV M2_HOME=/usr/share/maven
ENV PATH="${ANT_HOME}/bin:${GRADLE_HOME}/bin:${M2_HOME}/bin:${PATH}"

USER ${USER_NAME}

FROM agent-java AS agent-android

# Re-apply bash strict shell in new stage
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG USER_NAME

# Android SDK (ARGs still needed for sdkmanager selections, only cmdline-tools ZIP comes from JSON)
ARG ANDROID_COMPILE_SDK=36
ARG ANDROID_BUILD_TOOLS=36.0.0
ARG NDK_VERSION=29.0.14206865
ARG CMAKE_VERSION=4.1.2

COPY dependencies/android-sdk.json /tmp/android-sdk.json
RUN SDK_ARCH="${TARGETARCH}"; \
    SDK_VERSION=$(jq -r '.version' /tmp/android-sdk.json); \
    SDK_SHA256=$(jq -r ".sha256[\"${SDK_ARCH}\"]" /tmp/android-sdk.json); \
    DOWNLOAD_URL=$(jq -r '.download_url' /tmp/android-sdk.json | sed "s/{version}/${SDK_VERSION}/g"); \
    curl -fsSL "${DOWNLOAD_URL}" -o android-sdk.zip; \
    if [ -n "${SDK_SHA256}" ] && [ "${SDK_SHA256}" != "null" ]; then echo "${SDK_SHA256}  android-sdk.zip" | sha256sum -c -; fi; \
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
ENV ANDROID_COMPILE_SDK="${ANDROID_COMPILE_SDK}" ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS}" NDK_VERSION="${NDK_VERSION}" CMAKE_VERSION="${CMAKE_VERSION}"

ENV ANDROID_NDK="$ANDROID_SDK_ROOT/ndk/${NDK_VERSION}"
ENV PATH="${PATH}:$ANDROID_HOME/platform-tools"
ENV PATH="${PATH}:$ANDROID_SDK_ROOT/build-tools/${ANDROID_BUILD_TOOLS}:$ANDROID_NDK"

