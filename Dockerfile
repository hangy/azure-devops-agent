ARG ARG_UBUNTU_BASE_IMAGE="agent-base-image"

FROM ${ARG_UBUNTU_BASE_IMAGE} AS agent

USER root

WORKDIR /azp
COPY ./*.sh .

# Install Compose
RUN curl -L https://github.com/docker/compose/releases/download/v2.40.2/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose \
    && chmod +x /usr/local/bin/docker-compose \
    && docker-compose --version

# Install Kustomize
RUN wget -q https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh \
    && chmod a+rwx install_kustomize.sh \
    && ./install_kustomize.sh /usr/local/bin \
    && rm install_kustomize.sh \
    && kustomize version

USER azdouser
ENTRYPOINT ["./add-certs-and-start.sh"]

FROM agent AS agent-dotnet

# Add .NET
RUN wget https://dot.net/v1/dotnet-install.sh \
    && chmod +x dotnet-install.sh \
    && ./dotnet-install.sh --os linux --channel STS \
    && rm dotnet-install.sh
ENV PATH="/home/azdouser/.dotnet:${PATH}"

FROM agent-dotnet AS agent-java

USER root

# Add Java
RUN apt-get install openjdk-8-jdk-headless openjdk-17-jdk-headless openjdk-21-jdk-headless ant gradle maven \
    && update-java-alternatives -a \
    && rm -rf /var/lib/apt/lists/*
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
ENV ANDROID_COMPILE_SDK=36
ENV ANDROID_BUILD_TOOLS=36.0.0
ENV ANDROID_SDK_TOOLS=13114758
ENV NDK_VERSION=29.0.13599879
ENV CMAKE_VERSION=4.0.2

RUN \
    wget --quiet --output-document=android-sdk.zip https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_TOOLS}_latest.zip && \
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

ENV ANDROID_NDK="$ANDROID_SDK_ROOT/ndk/${NDK_VERSION}"
ENV PATH="${PATH}:$ANDROID_HOME/platform-tools"
ENV PATH="${PATH}:$ANDROID_SDK_ROOT/build-tools/${ANDROID_BUILD_TOOLS}:$ANDROID_NDK"

FROM agent-android AS agent-flutter

ENV FLUTTER_VERSION=3.35.7

USER root

RUN set -x && \
    apt-get update && \
    apt-get install -y curl git unzip xz-utils zip libglu1-mesa libc6:amd64 libstdc++6:amd64 lib32z1 libbz2-1.0:amd64 && \
    rm -rf /var/lib/apt/lists/*

USER azdouser

RUN set -x && \
    wget --quiet --output-document=flutter-sdk.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz && \
    tar -xf flutter-sdk.tar.xz -C /home/azdouser && \
    rm flutter-sdk.tar.xz

ENV FLUTTER_HOME="/home/azdouser/flutter"
ENV PATH="${PATH}:${FLUTTER_HOME}/bin"
