#!/usr/bin/env bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

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
%{ endif ~}
    volumes:
      - /opt/teamspeak-data:/var/tsserver
EOF

docker compose -f /opt/teamspeak/docker-compose.yaml pull
docker compose -f /opt/teamspeak/docker-compose.yaml up -d
