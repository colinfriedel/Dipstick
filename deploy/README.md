# Deploying Dipstick

The backend runs on a single small Linux VM (GCP "Always Free" `e2-micro`):
Postgres + both Go services + Caddy (automatic HTTPS), all via `docker compose`.
Images are the ones CI pushes to GHCR. DNS is two DuckDNS subdomains, kept
current by a container in the stack.

```
            DuckDNS A records
  cf-dipstick.duckdns.org ─────────┐
  cf-dipstick-activity.duckdns.org ┤ ──▶  VM external IP  ──▶  Caddy :80/:443
                                          (TLS, Let's Encrypt)
                                                │
                          ┌─────────────────────┴─────────────────────┐
                    vehicle-service:8080                    activity-service:8080
                          └─────────────────────┬─────────────────────┘
                                            Postgres
```

## One-time setup

### 1. The VM (Google Cloud console)

1. Create a project (e.g. `dipstick`). Enable the Compute Engine API when prompted.
2. **Compute Engine → VM instances → Create instance**:
   - **Name:** `dipstick`
   - **Region:** `us-west1` (or `us-central1` / `us-east1` — only these are free
     for `e2-micro`). **Zone:** any.
   - **Machine configuration:** series **E2**, type **e2-micro**.
   - **Boot disk → Change:** OS **Ubuntu**, version **Ubuntu 24.04 LTS**,
     **Standard persistent disk**, **30 GB**.
   - **Networking / Firewall:** check **Allow HTTP traffic** and
     **Allow HTTPS traffic**.
   - **Security → Manage access → Add manually generated SSH key:** paste your
     public key with `ubuntu` as the trailing username:
     `ssh-ed25519 AAAA...  ubuntu`
     (GCP uses the last field as the Linux username.)
3. Create. Note the **External IP**.

The external IP is ephemeral; the `duckdns` container re-points both names at the
current IP every 5 minutes, so a restart that changes it self-heals.

### 2. DuckDNS

Two subdomains already claimed: `cf-dipstick`, `cf-dipstick-activity`. Set each to
the VM's external IP once. Copy your **token** from the top of the page — it goes
in `deploy/.env`.

### 3. GitHub

- Make the two GHCR packages **public**
  (github.com/users/colinfriedel/packages → each package → Package settings →
  Change visibility). Then the VM pulls without authenticating.
- Add repo secrets (Settings → Secrets and variables → Actions):
  `DEPLOY_HOST` (external IP), `DEPLOY_USER` (`ubuntu`),
  `DEPLOY_SSH_KEY` (contents of `~/.ssh/dipstick_deploy`).

### 4. On the VM

```bash
ssh -i ~/.ssh/dipstick_deploy ubuntu@<EXTERNAL_IP>
curl -fsSL https://raw.githubusercontent.com/colinfriedel/Dipstick/main/deploy/bootstrap.sh | bash
# log out, back in (docker group)
cd ~/Dipstick/deploy
cp .env.example .env && nano .env      # Postgres password, your email, DuckDNS token
./deploy.sh
```

Caddy fetches certificates on first start (needs port 80 reachable). Check:

```bash
curl https://cf-dipstick.duckdns.org/healthz
curl https://cf-dipstick-activity.duckdns.org/healthz
```

## Ongoing

- **Automatic:** every push to `main` → CI tests, builds & pushes images, then
  the Deploy workflow SSHes in and runs `deploy.sh`.
- **Manual:** `ssh` in, `cd ~/Dipstick && git pull && ./deploy/deploy.sh`.
- **Roll back:** set `IMAGE_TAG=sha-<commit>` in `deploy/.env`, run `./deploy.sh`.
- **Logs:** `docker compose -f docker-compose.prod.yml logs -f <service>`.
- **DB backup:** `docker compose -f docker-compose.prod.yml exec postgres pg_dump -U dipstick dipstick | gzip > backup-$(date +%F).sql.gz`

## Notes on the free tier

- `e2-micro` is 1 GB RAM; `bootstrap.sh` adds a 2 GB swap file and Postgres runs
  with `max_connections=40`.
- GCP Always Free includes ~1 GB/month of outbound data. JSON API responses are
  tiny, so this is not a practical limit for personal use.
