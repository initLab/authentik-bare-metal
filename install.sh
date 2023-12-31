#!/bin/bash

set -e
set -x

: "${ARCH:=amd64}"
BASE_DIR=$HOME
DOTLOCAL=$BASE_DIR/.local
BIN_DIR="${DOTLOCAL}/bin"
SRC_DIR=$BASE_DIR/src

mkdir -p "$BIN_DIR"
PATH="${BIN_DIR}:${PATH}"

cd "$BASE_DIR"

if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 12, 1))' &>/dev/null
then
	wget -qO- https://www.python.org/ftp/python/3.12.1/Python-3.12.1.tgz | tar -zxf -
	cd Python-3.12.1
	./configure --enable-optimizations --prefix="$DOTLOCAL"
	make altinstall
	cd -
	rm -rf Python-3.12.1
	ln -s "${BIN_DIR}/python3.12" "${BIN_DIR}/python3"
fi

if ! command -v yq &>/dev/null
then
  YQ_LATEST="$(wget -qO- "https://api.github.com/repos/mikefarah/yq/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')"
  wget "https://github.com/mikefarah/yq/releases/download/${YQ_LATEST}/yq_linux_${ARCH}" -qO "$DOTLOCAL"/bin/yq
	chmod +x "$DOTLOCAL"/bin/yq
fi

if ! command -v node &>/dev/null
then
	wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
	export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
	[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
	nvm install v21
fi

if ! command -v go &>/dev/null
then
	GO_JSON=$(wget -qO- "https://golang.org/dl/?mode=json")
  GO_LATEST_VERSION=$(echo "$GO_JSON" | grep -Po '"version": "\K.*?(?=")' | head -1)
  GO_LATEST_URL=$(echo "$GO_JSON" | grep -Po '"filename": "\K.*?(?=")' | grep "linux-${ARCH}" | grep "$GO_LATEST_VERSION" | head -1)

  if [ -z "${GO_LATEST_URL}" ]
  then
    echo 'Golang install URL not found, please fix the script' >&2
    exit 1
  fi

  wget -qO- "https://golang.org/dl/${GO_LATEST_URL}" | tar -zxf -
  cp -prf go/* "${DOTLOCAL}"
  chmod -R u+w go
  rm -rf go
fi

if ! command -v pip &>/dev/null
then
	curl https://bootstrap.pypa.io/get-pip.py | python3
fi

if ! python3 -m virtualenv --version &>/dev/null
then
	python3 -m pip install virtualenv
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
	python3 -m virtualenv ./.venv
fi

curl https://bootstrap.pypa.io/get-pip.py | ./.venv/bin/python3
./.venv/bin/pip install --no-cache-dir poetry poetry-plugin-export
./.venv/bin/poetry export -f requirements.txt --output requirements.txt
./.venv/bin/poetry export -f requirements.txt --with dev --output requirements-dev.txt
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
ExecStart=/bin/bash -c 'source /home/authentik/src/.venv/bin/activate && python3 -m lifecycle.migrate && /home/authentik/src/authentik-server'
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
