#!/usr/bin/env bash
#
# One-time server setup for a fresh Ubuntu 24.04 Oracle Cloud VM.
# Run it on the server as the default user (e.g. `ubuntu`):
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

echo "==> Opening ports 80 and 443 in the host firewall"
# Oracle's Ubuntu images ship iptables rules that block everything but 22.
# (You ALSO need to open 80/443 in the VCN security list in the OCI console.)
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save || sudo sh -c 'iptables-save > /etc/iptables/rules.v4'

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
  3. cp .env.example .env  &&  edit .env  (Postgres password, the two DuckDNS
     domains, your email)
  4. ./deploy.sh
DONE
