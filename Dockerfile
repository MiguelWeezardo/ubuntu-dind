FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive
ARG NODE_VERSION="12 16"
ARG DISTRO=ubuntu
ARG TYPE=act

RUN apt update \
    && apt-get install -y tzdata \
    && apt install -y ca-certificates openssh-client \
    wget curl iptables supervisor jq ssh lsb-release \
    gawk curl git jq wget sudo gnupg-agent ca-certificates \
    software-properties-common apt-transport-https libyaml-0-2 \
    zstd zip unzip xz-utils \
    && rm -rf /var/lib/apt/list/*

COPY install_nodejs.sh ./install_nodejs.sh

RUN chmod 755 ./install_nodejs.sh && ./install_nodejs.sh

ENV DOCKER_CHANNEL=stable \
	DOCKER_VERSION=20.10.9 \
	DOCKER_COMPOSE_VERSION=1.29.2 \
	DEBUG=false

# Docker installation
RUN set -eux; \
	\
	arch="$(uname --m)"; \
	case "$arch" in \
        # amd64
		x86_64) dockerArch='x86_64' ;; \
        # arm32v6
		armhf) dockerArch='armel' ;; \
        # arm32v7
		armv7) dockerArch='armhf' ;; \
        # arm64v8
		aarch64) dockerArch='aarch64' ;; \
		*) echo >&2 "error: unsupported architecture ($arch)"; exit 1 ;;\
	esac; \
	\
	if ! wget -O docker.tgz "https://download.docker.com/linux/static/${DOCKER_CHANNEL}/${dockerArch}/docker-${DOCKER_VERSION}.tgz"; then \
		echo >&2 "error: failed to download 'docker-${DOCKER_VERSION}' from '${DOCKER_CHANNEL}' for '${dockerArch}'"; \
		exit 1; \
	fi; \
	\
	tar --extract \
		--file docker.tgz \
		--strip-components 1 \
		--directory /usr/local/bin/ \
	; \
	rm docker.tgz; \
	\
	dockerd --version; \
	docker --version

COPY modprobe startup.sh /usr/local/bin/
COPY supervisor/ /etc/supervisor/conf.d/
COPY logger.sh /opt/bash-utils/logger.sh

RUN chmod +x /usr/local/bin/startup.sh /usr/local/bin/modprobe
VOLUME /var/lib/docker

# Docker compose installation
RUN curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose \
	&& chmod +x /usr/local/bin/docker-compose && docker-compose version

ENTRYPOINT ["startup.sh"]
CMD ["sh"]
