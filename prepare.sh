#!/bin/bash

sudo apt update && sudo apt upgrade -yqq # Ensure up-to-date system
sudo apt install -yqq curl wget git build-essential libncursesw5-dev libssl-dev \
     libsqlite3-dev tk-dev libgdbm-dev libc6-dev libbz2-dev pkg-config libffi-dev zlib1g-dev libxmlsec1 libxmlsec1-dev libxmlsec1-openssl libmaxminddb0 # Install build dependencies

useradd --create-home --user-group --system --shell /bin/bash authentik
