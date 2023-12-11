#!/bin/bash

set -e
set -x

BASE_DIR=$HOME
PREFIX=$BASE_DIR/.local
SRC_DIR=$BASE_DIR/src

cd "$BASE_DIR"

if ! command -v python3.11 &>/dev/null
then
	wget -qO- https://www.python.org/ftp/python/3.11.1/Python-3.11.1.tgz | tar -zxf
	cd Python-3.11.1
	./configure --enable-optimizations --prefix="$PREFIX"
	sudo make altinstall # Install Python 3.11.1
	cd -
	rm -rf Python-3.11.1
fi

if ! command -v yq &>/dev/null
then
	wget https://github.com/mikefarah/yq/releases/download/v4.30.8/yq_linux_amd64 -qO "$PREFIX"/bin/yq
	chmod +x "$PREFIX"/bin/yq
fi

if ! command -v node &>/dev/null
then
	wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
	export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
	[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
	nvm install v18
fi

if ! command -v go &>/dev/null
then
	wget -qO- https://golang.org/dl/go1.19.linux-amd64.tar.gz | tar -zxf
fi

if ! command -v pip &>/dev/null
then
	curl https://bootstrap.pypa.io/get-pip.py | python3.11
fi

if ! command -v virtualenv &>/dev/null
then
	python3.11 -m pip install virtualenv
fi

if [ ! -d "$SRC_DIR" ]
then
	cd "$BASE_DIR"
	git clone https://github.com/goauthentik/authentik.git "$SRC_DIR"
	cd "$SRC_DIR"
else
	cd "$SRC_DIR"
	git pull --ff-only
fi

if [ ! -d .venv ]
then
	python3.11 -m virtualenv ./.venv
fi

./.venv/bin/pip install --no-cache-dir poetry
./.venv/bin/poetry export -f requirements.txt --output requirements.txt
./.venv/bin/poetry export -f requirements.txt --dev --output requirements-dev.txt
./.venv/bin/pip install --no-cache-dir -r requirements.txt -r requirements-dev.txt

cd "$SRC_DIR"/website
npm i
npm run build-docs-only

cd "$SRC_DIR"/web
npm i
npm run build

cd "$SRC_DIR"
go build -o "$SRC_DIR"/authentik-server  "$SRC_DIR"/cmd/server/

mkdir -p "$HOME"/.config/systemd/user

tee "$HOME"/.config/systemd/user/authentik-server.service > /dev/null << EOF
[Unit]
Description = Authentik Server (Web/API/SSO)

[Service]
ExecStart=/bin/bash -c 'source /home/authentik/src/.venv/bin/activate && python -m lifecycle.migrate && /home/authentik/src/authentik-server'
WorkingDirectory=/home/authentik/src

Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

tee "$HOME"/.config/systemd/user/authentik-worker.service > /dev/null << EOF
[Unit]
Description = Authentik Worker (background tasks)

[Service]
ExecStart=/bin/bash -c 'source /home/authentik/src/.venv/bin/activate && celery -A authentik.root.celery worker -Ofair --max-tasks-per-child=1 --autoscale 3,1 -E -B -s /tmp/celerybeat-schedule -Q authentik,authentik_scheduled,authentik_events'
WorkingDirectory=/home/authentik/src

Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

mkdir -p "$BASE_DIR"/{templates,certs}

CONFIG_FILE=$SRC_DIR/.local.env.yml

cp "$SRC_DIR"/authentik/lib/default.yml "$CONFIG_FILE"
cp -r "$SRC_DIR"/blueprints "$BASE_DIR"/blueprints

yq -i ".secret_key = \"$(openssl rand -hex 32)\"" "$CONFIG_FILE"

yq -i ".error_reporting.enabled = false" "$CONFIG_FILE"
yq -i ".disable_update_check = true" "$CONFIG_FILE"
yq -i ".disable_startup_analytics = true" "$CONFIG_FILE"
#yq -i ".avatars = \"none\"" "$CONFIG_FILE"

yq -i ".email.template_dir = \"${BASE_DIR}/templates\"" "$CONFIG_FILE"
yq -i ".cert_discovery_dir = \"${BASE_DIR}/certs\"" "$CONFIG_FILE"
yq -i ".blueprints_dir = \"${BASE_DIR}/blueprints\"" "$CONFIG_FILE"
yq -i ".geoip = \"/var/lib/GeoIP/GeoLite2-City.mmdb\""  "$CONFIG_FILE"
