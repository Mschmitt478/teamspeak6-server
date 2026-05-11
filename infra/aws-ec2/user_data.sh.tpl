#!/usr/bin/env bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release%{ if enable_apollo_bridge } nodejs npm%{ endif }

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

cat >/etc/apt/sources.list.d/docker.list <<'EOF'
deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable
EOF

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

mkdir -p /opt/teamspeak

DATA_DEVICE=""
for _ in $(seq 1 300); do
  for candidate in /dev/nvme1n1 /dev/xvdf /dev/sdf; do
    if [ -b "$candidate" ]; then
      DATA_DEVICE="$candidate"
      break 2
    fi
  done
  sleep 2
done

if [ -z "$DATA_DEVICE" ]; then
  echo "Timed out waiting for the TeamSpeak EBS data volume" >&2
  exit 1
fi

if ! blkid "$DATA_DEVICE"; then
  mkfs.ext4 -F "$DATA_DEVICE"
fi

mkdir -p /opt/teamspeak-data
UUID="$(blkid -s UUID -o value "$DATA_DEVICE")"
if ! grep -q "$UUID" /etc/fstab; then
  echo "UUID=$UUID /opt/teamspeak-data ext4 defaults,nofail 0 2" >>/etc/fstab
fi
mount /opt/teamspeak-data
mkdir -p /opt/teamspeak-data/logs
chown -R 1000:1000 /opt/teamspeak-data
chmod -R a+rwX /opt/teamspeak-data

cat >/opt/teamspeak/docker-compose.yaml <<'EOF'
services:
  teamspeak:
    image: teamspeaksystems/teamspeak6-server:latest
    container_name: teamspeak-server
    restart: unless-stopped
    ports:
      - "${voice_port}:${voice_port}/udp"
%{ if enable_file_transfer ~}
      - "${file_transfer_port}:${file_transfer_port}/tcp"
%{ endif ~}
%{ if enable_query_http ~}
      - "${query_http_port}:${query_http_port}/tcp"
%{ endif ~}
%{ if enable_query_ssh ~}
      - "${query_ssh_port}:${query_ssh_port}/tcp"
%{ endif ~}
    environment:
      - TSSERVER_LICENSE_ACCEPTED=accept
      - TSSERVER_DEFAULT_PORT=${voice_port}
      - TSSERVER_VOICE_IP=0.0.0.0
%{ if enable_file_transfer ~}
      - TSSERVER_FILE_TRANSFER_PORT=${file_transfer_port}
      - TSSERVER_FILE_TRANSFER_IP=0.0.0.0
%{ endif ~}
%{ if enable_query_http ~}
      - TSSERVER_QUERY_HTTP_ENABLED=true
      - TSSERVER_QUERY_HTTP_PORT=${query_http_port}
%{ endif ~}
%{ if enable_query_ssh ~}
      - TSSERVER_QUERY_SSH_ENABLED=true
      - TSSERVER_QUERY_SSH_PORT=${query_ssh_port}
      - TSSERVER_QUERY_ADMIN_PASSWORD=$${QUERY_ADMIN_PASSWORD}
%{ endif ~}
    volumes:
      - /opt/teamspeak-data:/var/tsserver
EOF

%{ if enable_query_ssh ~}
if [ ! -f /root/teamspeak-query-admin-password ]; then
  openssl rand -base64 36 >/root/teamspeak-query-admin-password
  chmod 600 /root/teamspeak-query-admin-password
fi
QUERY_ADMIN_PASSWORD="$(cat /root/teamspeak-query-admin-password)"
export QUERY_ADMIN_PASSWORD
printf '127.0.0.1\n::1\n' >/opt/teamspeak-data/query_ip_allowlist.txt
%{ endif ~}

docker compose -f /opt/teamspeak/docker-compose.yaml pull
docker compose -f /opt/teamspeak/docker-compose.yaml up -d

%{ if enable_apollo_bridge ~}
mkdir -p /opt/apollo-bridge
curl -fsSL "${apollo_bridge_source_base_url}/bridge.js" -o /opt/apollo-bridge/bridge.js
curl -fsSL "${apollo_bridge_source_base_url}/package.json" -o /opt/apollo-bridge/package.json
chmod 0644 /opt/apollo-bridge/bridge.js /opt/apollo-bridge/package.json

if [ ! -f /opt/apollo-bridge/.env.local ]; then
  cat >/opt/apollo-bridge/.env.local <<'EOF_APOLLO_BRIDGE_ENV'
TS_HOST=127.0.0.1
TS_QUERY_PORT=${query_ssh_port}
TS_QUERY_USER=serveradmin
TS_VIRTUAL_SERVER_ID=1
TS_CHANNEL_ID=${apollo_bridge_channel_id}
TS_QUERY_PASSWORD_COMMAND=sudo cat /root/teamspeak-query-admin-password
APOLLO_BRIDGE_PREFIX=${apollo_bridge_prefix}
APOLLO_BRIDGE_COMMAND_PREFIX=!apollo
APOLLO_BRIDGE_NICKNAME=Apollo
APOLLO_BRIDGE_OUTBOX_DIR=/opt/apollo-bridge/outbox
APOLLO_BRIDGE_MODE=openai
OPENAI_API_KEY=replace-me
OPENAI_MODEL=${apollo_bridge_openai_model}
EOF_APOLLO_BRIDGE_ENV
  chmod 600 /opt/apollo-bridge/.env.local
fi

cat >/etc/systemd/system/apollo-bridge.service <<'EOF_APOLLO_BRIDGE_SERVICE'
[Unit]
Description=ApolloBridge TeamSpeak text bridge
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=/opt/apollo-bridge
Environment=NODE_ENV=production
ExecStartPre=/bin/bash -lc 'test -f /opt/apollo-bridge/.env.local && ! grep -q "OPENAI_API_KEY=replace-me" /opt/apollo-bridge/.env.local'
ExecStart=/usr/bin/node /opt/apollo-bridge/bridge.js
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF_APOLLO_BRIDGE_SERVICE

systemctl daemon-reload
systemctl enable apollo-bridge.service
if ! systemctl start apollo-bridge.service; then
  echo "ApolloBridge installed but not started. Add OPENAI_API_KEY to /opt/apollo-bridge/.env.local, then run: systemctl start apollo-bridge" >&2
fi
%{ endif ~}
