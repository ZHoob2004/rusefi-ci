FROM ubuntu:22.04 AS builder

ARG RUNNER_VERSION="2.302.1"

WORKDIR /build

COPY start.sh /opt/start.sh

ADD https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz /build/

ADD https://raw.githubusercontent.com/rusefi/rusefi/master/firmware/provide_gcc.sh /build/

RUN apt-get update &&\
    apt-get -y install curl xz-utils &&\
    mkdir -p /opt/actions-runner &&\
    tar -xf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -C /opt/actions-runner/ &&\
    bash provide_gcc.sh &&\
    chmod +x /opt/start.sh



FROM ubuntu:22.04 AS actions-runer

COPY --from=builder /opt /opt
COPY --from=builder /tmp/rusefi-provide_gcc /tmp/rusefi-provide_gcc

ENV JAVA_HOME /usr/lib/jvm/temurin-11-jdk-amd64/

ARG GID=1000

RUN groupadd docker -g $GID &&\
    useradd -m -g docker -G sudo docker &&\
    apt-get update -y &&\
    apt-get install -y wget gpg &&\
    wget -O key.gpg https://packages.adoptium.net/artifactory/api/gpg/key/public &&\
    gpg --dearmor -o /usr/share/keyrings/adoptium.gpg key.gpg &&\
    echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" >/etc/apt/sources.list.d/adoptium.list &&\
    apt-get update -y &&\
    DEBIAN_FRONTEND=noninteractive /opt/actions-runner/bin/installdependencies.sh && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    curl \
    jq \
    build-essential \
    git \
    gcc \
    make \
    openjdk-8-jdk-headless \
    ant \
    mtools \
    dosfstools \
    zip \
    xxd \
    usbutils \
    openocd \
    sudo \
    ruby-rubygems \
    time \
    lsb-release \
    file \
    netbase \
    gcc-multilib \
    g++-multilib \
    g++-mingw-w64 \
    gcc-mingw-w64 \
    sshpass \
    doxygen \
    graphviz \
    lcov \
    valgrind \
    python3-pip \
    python3-tk \
    scour \
    librsvg2-bin \
    temurin-11-jdk \
    uidmap \
    supervisor \
    iproute2 \
    openssh-client \
    software-properties-common \
    && apt-get autoremove -y && apt-get clean -y &&\
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers &&\
    echo 'APT::Get::Assume-Yes "true";' >/etc/apt/apt.conf.d/90forceyes &&\
    chown -R docker /opt &&\
    chown -R docker /tmp/rusefi-provide_gcc &&\
    update-alternatives --set java /usr/lib/jvm/temurin-11-jdk-amd64/bin/java

# Install Docker CLI
RUN curl -fsSL https://get.docker.com -o- | sh && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Install Docker-Compose
RUN curl -L -o /usr/local/bin/docker-compose \
    "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" && \
    chmod +x /usr/local/bin/docker-compose

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN chmod 644 /etc/supervisor/conf.d/supervisord.conf

WORKDIR /opt

USER docker

RUN dockerd-rootless-setuptool.sh install

VOLUME /opt/actions-runner

ENTRYPOINT ["./start.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
