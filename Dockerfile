ARG ARG_UBUNTU_BASE_IMAGE="agent-base-image"

FROM ${ARG_UBUNTU_BASE_IMAGE}

USER root

WORKDIR /azp
COPY ./*.sh .
RUN chmod +x add-certs-and-start.sh import-pem-to-keystore.sh

# Install Compose
RUN curl -L https://github.com/docker/compose/releases/download/v2.33.1/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose \
    && chmod +x /usr/local/bin/docker-compose \
    && docker-compose --version

# Install Kustomize
RUN wget -q https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh \
    && chmod a+rwx install_kustomize.sh \
    && ./install_kustomize.sh /usr/local/bin \
    && rm install_kustomize.sh \
    && kustomize version

# Add Java
RUN apt-get install openjdk-8-jdk-headless openjdk-17-jdk-headless openjdk-21-jdk-headless ant gradle maven \
    && update-java-alternatives -a \
    && apt-get clean
ENV JAVA_HOME_8_X64=/usr/lib/jvm/java-8-openjdk-amd64
ENV JAVA_HOME_17_X64=/usr/lib/jvm/java-17-openjdk-amd64
ENV JAVA_HOME_21_X64=/usr/lib/jvm/java-21-openjdk-amd64
ENV JAVA_HOME=${JAVA_HOME_21_X64}
ENV ANT_HOME=/usr/share/ant
ENV GRADLE_HOME=/usr/share/gradle
ENV M2_HOME=/usr/share/maven
ENV PATH="${ANT_HOME}/bin:${GRADLE_HOME}/bin:${M2_HOME}/bin:${PATH}"

USER azdouser

# Add .NET
RUN wget https://dot.net/v1/dotnet-install.sh \
    && chmod +x dotnet-install.sh \
    && ./dotnet-install.sh --os linux --channel STS \
    && rm dotnet-install.sh
ENV PATH="/home/azdouser/.dotnet:${PATH}"

ENTRYPOINT ["./add-certs-and-start.sh"]
