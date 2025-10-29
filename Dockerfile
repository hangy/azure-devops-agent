# syntax=docker/dockerfile:1
ARG ARG_UBUNTU_BASE_IMAGE="agent-base-image"
ARG VCS_REF
ARG BUILD_DATE
ARG VSTS_AGENT_VERSION

FROM ${ARG_UBUNTU_BASE_IMAGE} AS agent

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
    set -euo pipefail; \
    apt-get update && \
    apt-get install ${APT_FLAGS} ca-certificates curl git unzip

# Install Compose
ARG TARGETARCH
RUN set -euo pipefail; \
        COMPOSE_ARCH="${TARGETARCH}"; \
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
RUN set -euo pipefail; \
    curl -fsSL https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh \
    -o install_kustomize.sh && \
    chmod a+rwx install_kustomize.sh && \
    ./install_kustomize.sh /usr/local/bin && \
    rm install_kustomize.sh && \
    kustomize version

USER azdouser
ENTRYPOINT ["./add-certs-and-start.sh"]

FROM agent AS agent-dotnet

# Add .NET
RUN set -euo pipefail; \
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh && \
    chmod +x dotnet-install.sh && \
    ./dotnet-install.sh --os linux --channel STS && \
    rm dotnet-install.sh
ENV PATH="/home/azdouser/.dotnet:${PATH}"

FROM agent-dotnet AS agent-java

USER root

# Add Java
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
        --mount=type=cache,target=/var/lib/apt \
        set -euo pipefail; \
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

# Android SDK
ARG ANDROID_COMPILE_SDK=36
ARG ANDROID_BUILD_TOOLS=36.0.0
ARG ANDROID_SDK_TOOLS=13114758
ARG NDK_VERSION=29.0.14206865
ARG CMAKE_VERSION=4.1.2
ARG ANDROID_SDK_ZIP_SHA256=""
ARG ANDROID_NDK_SHA256="" # placeholder; SDK manager handles NDK integrity

RUN set -euo pipefail; \
    curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_TOOLS}_latest.zip" -o android-sdk.zip && \
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

ARG FLUTTER_VERSION=3.35.7
ARG FLUTTER_TAR_SHA256=""

USER root

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
        --mount=type=cache,target=/var/lib/apt \
        set -euo pipefail; \
        apt-get update && \
        apt-get install ${APT_FLAGS} \
            lib32z1 \
            libbz2-1.0:amd64 \
            libc6:amd64 \
            libglu1-mesa \
            libstdc++6:amd64 \
            xz-utils \
            zip

USER azdouser

RUN set -euo pipefail; \
    curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o flutter-sdk.tar.xz && \
    if [ -n "${FLUTTER_TAR_SHA256}" ]; then echo "${FLUTTER_TAR_SHA256}  flutter-sdk.tar.xz" | sha256sum -c -; fi && \
    tar -xf flutter-sdk.tar.xz -C /home/azdouser && \
    rm flutter-sdk.tar.xz

ENV FLUTTER_HOME="/home/azdouser/flutter"
ENV PATH="${PATH}:${FLUTTER_HOME}/bin"
