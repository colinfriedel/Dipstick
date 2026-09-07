#!/usr/bin/env bash
#
# One-time server setup for a fresh Ubuntu 24.04 VM (GCP e2-micro free tier, or
# any small Linux box). Run it on the server as the login user:
#
#   curl -fsSL https://raw.githubusercontent.com/colinfriedel/Dipstick/main/deploy/bootstrap.sh | bash
#
# or clone the repo first and run ./deploy/bootstrap.sh.
#
# After it finishes: log out and back in (for the docker group), then
#   cd ~/Dipstick/deploy && cp .env.example .env && nano .env && ./deploy.sh

set -euo pipefail

REPO_URL="https://github.com/colinfriedel/Dipstick.git"
CHECKOUT="$HOME/Dipstick"

echo "==> Adding a 2 GB swap file (the e2-micro only has 1 GB RAM)"
if ! sudo swapon --show | grep -q '/swapfile'; then
  sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
fi

echo "==> Installing Docker Engine + Compose plugin"
if ! command -v docker >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl git
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

echo "==> Adding $USER to the docker group"
sudo usermod -aG docker "$USER"

# Some cloud images (e.g. Oracle's) ship iptables rules that REJECT inbound
# traffic; GCP's don't. Only punch holes if there's actually a REJECT to beat —
# on GCP the network firewall (the "Allow HTTP/HTTPS" rules) is what matters.
if sudo iptables -S INPUT 2>/dev/null | grep -qE '\-j (REJECT|DROP)'; then
  echo "==> Opening ports 80 and 443 in the host firewall"
  sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
  sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
  sudo netfilter-persistent save 2>/dev/null \
    || { sudo mkdir -p /etc/iptables && sudo sh -c 'iptables-save > /etc/iptables/rules.v4'; }
fi

echo "==> Cloning the repo to $CHECKOUT"
if [[ -d "$CHECKOUT/.git" ]]; then
  git -C "$CHECKOUT" pull --ff-only
else
  git clone "$REPO_URL" "$CHECKOUT"
fi

cat <<'DONE'

==> Done.

Next:
  1. Log out and back in (so the docker group takes effect).
  2. cd ~/Dipstick/deploy
  3. cp .env.example .env  &&  edit .env
     (Postgres password, ACME email, DuckDNS token)
  4. ./deploy.sh
DONE
