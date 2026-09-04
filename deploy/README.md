# Deploying Dipstick

The backend runs on a single Oracle Cloud "Always Free" VM: Postgres + both Go
services + Caddy (for automatic HTTPS), all via `docker compose`. Images are the
ones CI pushes to GHCR. DNS is two DuckDNS subdomains.

```
            DuckDNS A records
  dipstick.duckdns.org ─────────┐
  dipstick-activity.duckdns.org ┤ ──▶  VM public IP  ──▶  Caddy :80/:443
                                        (TLS, Let's Encrypt)
                                              │
                          ┌───────────────────┴───────────────────┐
                    vehicle-service:8080                  activity-service:8080
                          └───────────────────┬───────────────────┘
                                          Postgres
```

## One-time setup

### On Oracle Cloud (console)

1. Create a VM: Ubuntu 24.04, shape `VM.Standard.A1.Flex` (1 OCPU / 6 GB — free)
   or `VM.Standard.E2.1.Micro` if A1 is out of capacity. Paste
   `~/.ssh/dipstick_deploy.pub` as the SSH key.
2. Reserve the public IP (Instance → attached VNIC → IPv4 → Edit → make it
   reserved) so it survives a stop/start.
3. Open ingress for TCP **80** and **443** from `0.0.0.0/0` in the subnet's
   Security List (only 22 is open by default).

### DuckDNS

Create two subdomains (`dipstick`, `dipstick-activity`), both pointing at the
VM's public IP.

### GitHub

- Make the two GHCR packages **public**
  (github.com/users/colinfriedel/packages → each package → Package settings →
  Change visibility). Then the VM pulls without authenticating.
- Add repo secrets: `DEPLOY_HOST` (VM IP), `DEPLOY_USER` (`ubuntu`),
  `DEPLOY_SSH_KEY` (contents of `~/.ssh/dipstick_deploy`).

### On the VM

```bash
ssh -i ~/.ssh/dipstick_deploy ubuntu@<VM_IP>
curl -fsSL https://raw.githubusercontent.com/colinfriedel/Dipstick/main/deploy/bootstrap.sh | bash
# log out, back in
cd ~/Dipstick/deploy
cp .env.example .env && nano .env      # password, the two domains, your email
./deploy.sh
```

Caddy gets certificates on first start (needs port 80 reachable). Check:

```bash
curl https://dipstick.duckdns.org/healthz
curl https://dipstick-activity.duckdns.org/healthz
```

## Ongoing

- **Automatic:** every push to `main` → CI tests, builds & pushes images, then
  the Deploy workflow SSHes in and runs `deploy.sh`.
- **Manual:** `ssh` in, `cd ~/Dipstick && git pull && ./deploy/deploy.sh`.
- **Roll back:** set `IMAGE_TAG=sha-<commit>` in `deploy/.env`, run `./deploy.sh`.
- **Logs:** `docker compose -f docker-compose.prod.yml logs -f <service>`.
- **DB backup:** `docker compose -f docker-compose.prod.yml exec postgres pg_dump -U dipstick dipstick | gzip > backup-$(date +%F).sql.gz`
