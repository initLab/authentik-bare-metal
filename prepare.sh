#!/bin/bash

set -e
set -x

if [ "$(id -u)" -ne 0 ]
then
  echo 'Please run as root!' >&2
  exit 1
fi

apt update

# Ensure up-to-date system
apt upgrade -y

# Install build dependencies
apt install -y curl wget git build-essential libncursesw5-dev libssl-dev \
  libsqlite3-dev tk-dev libgdbm-dev libc6-dev libbz2-dev pkg-config \
  libffi-dev zlib1g-dev libxmlsec1 libxmlsec1-dev libxmlsec1-openssl \
  libmaxminddb0

if ! id authentik &>/dev/null;
then
  useradd --create-home --user-group --system --shell /bin/bash authentik
fi
