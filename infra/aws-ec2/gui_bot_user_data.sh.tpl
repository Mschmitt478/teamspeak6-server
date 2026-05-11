#!/usr/bin/env bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
  ca-certificates \
  curl \
  tar \
  xz-utils \
  xvfb \
  openbox \
  x11vnc \
  xdotool \
  wmctrl \
  scrot \
  tesseract-ocr \
  pulseaudio \
  pulseaudio-utils \
  alsa-utils \
  dbus-x11 \
  jq \
  nodejs \
  npm

useradd --system --create-home --home-dir /opt/apollo-gui-bot --shell /bin/bash apollogui || true
install -d -o apollogui -g apollogui /opt/apollo-gui-bot /opt/teamspeak-client

cat >/opt/apollo-gui-bot/.env.local <<'EOF_ENV'
# Host-local secrets/config. Terraform intentionally writes placeholders only.
TS_SERVER_ADDRESS=${teamspeak_address}
TS_ACCOUNT_EMAIL=replace-me
TS_ACCOUNT_PASSWORD=replace-me
TS_CHANNEL_NAME=ApolloChat
TS_CHANNEL_PASSWORD=replace-me
DISPLAY=${display}
PULSE_RUNTIME_PATH=/run/user/$(id -u apollogui)/pulse
EOF_ENV
chmod 600 /opt/apollo-gui-bot/.env.local
chown apollogui:apollogui /opt/apollo-gui-bot/.env.local

cat >/usr/local/bin/apollo-gui-display <<'EOF_DISPLAY'
#!/usr/bin/env bash
set -euo pipefail
exec /usr/bin/Xvfb ${display} -screen 0 ${screen_geometry} -nolisten tcp
EOF_DISPLAY
chmod 755 /usr/local/bin/apollo-gui-display

cat >/usr/local/bin/apollo-gui-window-manager <<'EOF_WM'
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY=${display}
exec /usr/bin/openbox
EOF_WM
chmod 755 /usr/local/bin/apollo-gui-window-manager

%{ if enable_vnc ~}
cat >/usr/local/bin/apollo-gui-vnc <<'EOF_VNC'
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY=${display}
exec /usr/bin/x11vnc -display ${display} -localhost -forever -shared -rfbport ${vnc_port} -nopw
EOF_VNC
chmod 755 /usr/local/bin/apollo-gui-vnc
%{ endif ~}

cat >/usr/local/bin/install-teamspeak-client <<'EOF_INSTALL_TS'
#!/usr/bin/env bash
set -euo pipefail
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL "${client_download_url}" -o "$work/teamspeak-client.tar.gz"
%{ if client_sha256 != "" ~}
echo "${client_sha256}  $work/teamspeak-client.tar.gz" | sha256sum -c -
%{ endif ~}
tar -xzf "$work/teamspeak-client.tar.gz" -C "$work"
rm -rf /opt/teamspeak-client/*
# The archive layout can change between TS6 beta builds; copy likely payloads defensively.
if [ -d "$work/TeamSpeak" ]; then
  cp -a "$work/TeamSpeak/." /opt/teamspeak-client/
else
  find "$work" -mindepth 1 -maxdepth 2 -type f -perm -111 -print -quit >/tmp/ts-client-entry || true
  cp -a "$work/." /opt/teamspeak-client/
fi
chown -R apollogui:apollogui /opt/teamspeak-client
EOF_INSTALL_TS
chmod 755 /usr/local/bin/install-teamspeak-client

/usr/local/bin/install-teamspeak-client || true

cat >/usr/local/bin/apollo-gui-client <<'EOF_CLIENT'
#!/usr/bin/env bash
set -euo pipefail
source /opt/apollo-gui-bot/.env.local
export DISPLAY="${display}"
export XDG_RUNTIME_DIR="/run/user/$(id -u apollogui)"
mkdir -p "$XDG_RUNTIME_DIR"
chown apollogui:apollogui "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Find a TS client binary without assuming beta archive internals.
client_bin=""
for candidate in \
  /opt/teamspeak-client/TeamSpeak \
  /opt/teamspeak-client/teamspeak-client \
  /opt/teamspeak-client/ts3client_runscript.sh \
  /opt/teamspeak-client/ts3client_runpath_linux_amd64 \
  /opt/teamspeak-client/TeamSpeak/ts3client_runscript.sh \
  /opt/teamspeak-client/TeamSpeak/ts3client_runpath_linux_amd64; do
  if [ -x "$candidate" ]; then client_bin="$candidate"; break; fi
done
if [ -z "$client_bin" ]; then
  client_bin="$(find /opt/teamspeak-client -type f -perm -111 | head -1 || true)"
fi
if [ -z "$client_bin" ]; then
  echo "No TeamSpeak client executable found under /opt/teamspeak-client" >&2
  exit 1
fi
cd "$(dirname "$client_bin")"
exec "$client_bin"
EOF_CLIENT
chmod 755 /usr/local/bin/apollo-gui-client

cat >/usr/local/bin/apollo-gui-screenshot <<'EOF_SCREENSHOT'
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY=${display}
out="$${1:-/opt/apollo-gui-bot/screenshot.png}"
scrot "$out"
chown apollogui:apollogui "$out" || true
echo "$out"
EOF_SCREENSHOT
chmod 755 /usr/local/bin/apollo-gui-screenshot

cat >/usr/local/bin/apollo-gui-ocr <<'EOF_OCR'
#!/usr/bin/env bash
set -euo pipefail
img="$(apollo-gui-screenshot /tmp/apollo-gui-ocr.png)"
tesseract "$img" stdout 2>/dev/null || true
EOF_OCR
chmod 755 /usr/local/bin/apollo-gui-ocr

cat >/usr/local/bin/apollo-gui-click-type <<'EOF_CLICK_TYPE'
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY=${display}
text="$*"
xdotool type --delay 1 "$text"
xdotool key Return
EOF_CLICK_TYPE
chmod 755 /usr/local/bin/apollo-gui-click-type

cat >/etc/systemd/system/apollo-gui-display.service <<'EOF_SYSTEMD_DISPLAY'
[Unit]
Description=Apollo GUI virtual display
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/apollo-gui-display
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF_SYSTEMD_DISPLAY

cat >/etc/systemd/system/apollo-gui-window-manager.service <<'EOF_SYSTEMD_WM'
[Unit]
Description=Apollo GUI window manager
After=apollo-gui-display.service
Requires=apollo-gui-display.service

[Service]
Type=simple
User=apollogui
Environment=DISPLAY=${display}
ExecStart=/usr/local/bin/apollo-gui-window-manager
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_SYSTEMD_WM

%{ if enable_vnc ~}
cat >/etc/systemd/system/apollo-gui-vnc.service <<'EOF_SYSTEMD_VNC'
[Unit]
Description=Apollo GUI localhost VNC server
After=apollo-gui-display.service
Requires=apollo-gui-display.service

[Service]
Type=simple
User=apollogui
Environment=DISPLAY=${display}
ExecStart=/usr/local/bin/apollo-gui-vnc
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_SYSTEMD_VNC
%{ endif ~}

cat >/etc/systemd/system/apollo-gui-client.service <<'EOF_SYSTEMD_CLIENT'
[Unit]
Description=Apollo real TeamSpeak GUI client presence layer
After=apollo-gui-display.service apollo-gui-window-manager.service network-online.target
Requires=apollo-gui-display.service apollo-gui-window-manager.service
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStartPre=/bin/bash -lc 'test -f /opt/apollo-gui-bot/.env.local && ! grep -q "replace-me" /opt/apollo-gui-bot/.env.local'
ExecStart=/usr/local/bin/apollo-gui-client
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF_SYSTEMD_CLIENT

systemctl daemon-reload
systemctl enable --now apollo-gui-display.service apollo-gui-window-manager.service
%{ if enable_vnc ~}
systemctl enable --now apollo-gui-vnc.service
%{ endif ~}
systemctl enable apollo-gui-client.service
if ! systemctl start apollo-gui-client.service; then
  echo "Apollo GUI client host installed. Edit /opt/apollo-gui-bot/.env.local with TS account/channel credentials, then run: systemctl start apollo-gui-client" >&2
fi
