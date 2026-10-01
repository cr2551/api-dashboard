# Deploying the backend

How to run `server/bin/serve.dart` on a server that is reachable from the internet, over HTTPS, with the API token required, the SQLite history kept, and everything coming back by itself after a crash or a reboot ([#32](https://github.com/cr2551/api-dashboard/issues/32)).

## What runs

```
Internet ──https──> Caddy (:443, :80 redirects) ──http, private network──> monitor (:8080) ──> SQLite in volume monitor-data
```

| Requirement | How it is met |
|---|---|
| Reachable from outside | [Caddy](https://caddyserver.com) listens on ports 80 and 443 and forwards to the monitor. |
| HTTPS | Caddy gets a free Let's Encrypt certificate for your domain, renews it, redirects `http://` to `https://` and sends HSTS. |
| Auth enabled | `API_TOKEN` is set, so every request needs `Authorization: Bearer <token>`. The server **refuses to start** when it listens on the network (`HOST=0.0.0.0`) without a token. |
| Key not exposed | The token is generated on the server into `deploy/.env` (mode 600, git-ignored, never typed into a URL or committed). The monitor's port is not published, so plain HTTP never leaves the host, and Caddy never sees the token. |
| Persistent SQLite | `DB_PATH=/data/probes.db` in the named Docker volume `monitor-data`, which survives restarts, rebuilds and reboots. |
| Restarts on boot | Docker starts at boot (systemd), and both containers have `restart: always`, which also restarts them after a crash. The server stops cleanly on `SIGTERM`. |

The files: [compose.yaml](compose.yaml) (the two services), [Caddyfile](Caddyfile) (HTTPS proxy), [.env.example](.env.example) (settings and secrets template), [setup.sh](setup.sh) (first start and updates), [check.sh](check.sh) (tests a deployment from outside), and [../server/Dockerfile](../server/Dockerfile) (compiles the server ahead of time and runs it as an unprivileged user).

## Choosing a host

Any always-on Linux machine with Docker, a public IP and ports 80 and 443 open works the same way; only step 1 differs.

| Host | Cost | Notes |
|---|---|---|
| **Google Cloud `e2-micro` (recommended)** | Free tier, always on (`us-west1`, `us-central1` or `us-east1`, 30 GB standard disk). Check Google's current free-tier page: an external IPv4 address may carry a small charge. | Real public IP, nothing at home to configure. 1 GB of RAM is enough (the image build was tested under a 1 GB memory limit). Needs a Google account with billing enabled. |
| Oracle Cloud Always Free VM | Free | More RAM, but sign-up and free capacity can be hit and miss. |
| Raspberry Pi (64-bit OS) at home | Hardware only | Needs router port forwarding for 80 and 443 and a dynamic DNS name (DuckDNS). The steps below work unchanged on arm64. |
| Any paid VPS (Hetzner, DigitalOcean, ...) | A few dollars a month | Same steps as Google Cloud. |

Render's and Railway's free tiers are not used: they sleep or have no persistent disk, so the monitor would stop probing and lose its SQLite file.

## Steps

### 1. Create the server (Google Cloud)

1. In the Google Cloud console, open **Compute Engine > VM instances > Create instance**.
2. Name `sla-monitor`, region `us-central1` (or another free-tier region), machine type **e2-micro**.
3. Boot disk: **Ubuntu 24.04 LTS**, **standard persistent disk**, 30 GB.
4. Firewall: tick **Allow HTTP traffic** and **Allow HTTPS traffic**.
5. Create it, then under **VPC network > IP addresses** promote its external IP to **static**, so the DNS name below keeps working after a stop and start.
6. Connect with the **SSH** button. Everything below runs on the server.

Raspberry Pi instead: install Raspberry Pi OS Lite (64-bit), give the Pi a fixed LAN address, and forward TCP 80 and 443 (and UDP 443) on the router to it.

### 2. Point a domain at it

Caddy needs a hostname to get a certificate for. Pick one:

- **DuckDNS** (free, recommended): sign in at [duckdns.org](https://www.duckdns.org), create a subdomain such as `my-sla-monitor`, set its IP to the server's external IP. Your domain is `my-sla-monitor.duckdns.org`.
- **sslip.io** (no sign-up): `34-56-78-90.sslip.io` resolves to `34.56.78.90`. Use your IP with dashes.
- Your own domain: an `A` record pointing at the server.

Check from your own computer that `nslookup <domain>` returns the server's IP before going on.

### 3. Install Docker and Git

```bash
sudo apt-get update && sudo apt-get install -y git
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl enable --now docker containerd
sudo usermod -aG docker "$USER"
```

Log out and back in (close the SSH window and reopen it) so the `docker` group applies, then check that `docker compose version` works without `sudo`. `systemctl enable` is what makes Docker, and with it the monitor, start at boot.

Optional but sensible on a 1 GB machine: a swap file, so a build on a busy day cannot run out of memory.

```bash
sudo fallocate -l 1G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### 4. Get the code and choose what to monitor

```bash
git clone https://github.com/cr2551/api-dashboard.git
cd api-dashboard
cp services.example.json deploy/services.json
nano deploy/services.json
```

`deploy/services.json` is git-ignored, so it is yours to edit (fields: [Services config](../README.md#services-config)). The example monitors Stripe, which needs a test-mode key in step 5; without one, delete the `stripe` entry.

### 5. Configure and start

```bash
sh deploy/setup.sh <your-domain>
```

On the first run this creates `deploy/.env` (mode 600) from [.env.example](.env.example) with your domain and a fresh random `API_TOKEN`, then builds the image and starts both containers. If `services.json` has a Stripe service, it stops and asks for the key first:

```bash
nano deploy/.env          # STRIPE_API_KEY=sk_test_..., and optionally NTFY_TOPIC
sh deploy/setup.sh
```

Watch it come up (Ctrl+C leaves it running):

```bash
cd deploy && docker compose logs -f
```

You should see `API requires a bearer token`, one `ok` line per probe, and Caddy's `certificate obtained successfully` for your domain.

### 6. Check it from outside

From your own computer (Git Bash, macOS or Linux), in a clone of the repo:

```bash
sh deploy/check.sh <your-domain>
```

It prompts for the token (read it on the server with `grep API_TOKEN deploy/.env`) and checks that `http://` redirects to `https://` (308), that a request without the token gets 401, and that the token gets 200. Or by hand:

```bash
curl -i https://<your-domain>/api/status
curl -H "Authorization: Bearer <token>" https://<your-domain>/api/status
```

### 7. Check it survives a reboot

```bash
sudo reboot
```

Reconnect after a minute, then `cd api-dashboard/deploy && docker compose ps` shows both containers `Up` again without you starting them, and `/api/history` still has the probes from before the reboot.

### 8. Use it from the dashboard

```bash
flutter run -d chrome --dart-define=API_BASE_URL=https://<your-domain>
```

On the 401 screen choose **Enter access token** and paste the token. The CORS headers already allow the dashboard to call the API from another origin.

## Day-to-day

| Task | Command (in `api-dashboard/deploy`) |
|---|---|
| Logs | `docker compose logs -f monitor` |
| Status | `docker compose ps` |
| Update to the latest code | `git pull && sh setup.sh` (rebuilds and restarts; the database is kept) |
| Change monitored services or settings | edit `services.json` or `.env`, then `docker compose up -d --force-recreate monitor` |
| Rotate the token | put a new `openssl rand -hex 32` in `.env`, then `docker compose up -d --force-recreate monitor`, and enter it again in the app |
| Back up the database | `docker compose stop monitor && docker compose cp monitor:/data/probes.db ./probes-$(date +%F).db && docker compose start monitor` |
| Stop everything | `docker compose down` (keeps the volumes; `down -v` would **delete the database and certificates**) |

## Keeping the token private

- Generate it on the server; do not paste it into chat, issues, commits or URLs. The repo is public, and `.env` and `services.json` are git-ignored for that reason.
- Only ever call the API with `https://`. A request to `http://` is redirected, but its headers have already crossed the network in clear text.
- `deploy/.env` is readable only by its owner (setup.sh re-applies `chmod 600`). Anyone in the server's `docker` group can read container settings, so keep that group to yourself.
- The server never logs the token, and Caddy does not log request headers here.
- If it leaks, rotate it (see above); the old one stops working as soon as the container is recreated.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Invalid config at HOST: ... API_TOKEN must be set` | `API_TOKEN` is empty in `.env`. |
| `Invalid config at stripe: needs a Stripe key` | Add `STRIPE_API_KEY` to `.env` or remove the `stripe` service. |
| `Invalid config at /config/services.json: file not found` | Create `deploy/services.json` (step 4). If Docker created a *folder* by that name, delete it first. |
| Caddy logs `challenge failed` or `no such host` | The domain does not resolve to this server yet, or ports 80/443 are blocked (cloud firewall, router forwarding). Fix it and run `docker compose restart caddy`. |
| Build stops with `Killed` | Out of memory: add the swap file from step 3. |
| `permission denied ... docker.sock` | Log out and back in after `usermod -aG docker`. |
