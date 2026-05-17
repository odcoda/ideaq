# Idea Queue Sync Server

Small Flask sync server for one-person Idea Queue state. It stores snapshots in one SQLite database and exposes the same snapshot API used by the iOS and web clients.

## What It Does

- stores JSON files from `queue/`, `completed/`, and `projects/`
- protects reads and writes with one bearer token
- keeps snapshot revisions so stale clients can be merged instead of blindly overwriting
- merges queue JSON semantically where possible:
  - project order lists are merged as ordered unions
  - idea arrays are merged by `name`
  - fields use three-way merge rules
  - `related` arrays preserve values from both sides
  - same-field scalar conflicts use the latest uploading client value

The database is a single SQLite file. That is intentional: one user, low traffic, easy backup.

## API

```http
GET /v1/stores/{storeID}/snapshot
Authorization: Bearer <token>
```

```json
{
  "revision": "opaque-server-revision",
  "files": {
    "queue/PROJECTS.json": "[\"ksink\"]\n",
    "queue/ksink.json": "[]\n"
  }
}
```

```http
PUT /v1/stores/{storeID}/snapshot
Authorization: Bearer <token>
Content-Type: application/json
```

```json
{
  "base_revision": "revision-fetched-before-editing",
  "files": {
    "queue/PROJECTS.json": "[\"ksink\"]\n",
    "queue/ksink.json": "[]\n"
  },
  "client_base_files": {
    "queue/PROJECTS.json": "[]\n"
  }
}
```

`client_base_files` is optional for old clients, but current web and iOS clients send it so the server can do a proper three-way merge.

## Local Run

```sh
cd /Users/odile/projects/ideaq
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
export IDEAQ_SYNC_TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
export IDEAQ_SERVER_DB=/tmp/ideaq-sync.sqlite3
.venv/bin/python server/app.py --host 127.0.0.1 --port 8050 --no-debug
```

Test it:

```sh
curl -H "Authorization: Bearer $IDEAQ_SYNC_TOKEN" \
  http://127.0.0.1:8050/v1/stores/default/snapshot
```

## AWS EC2 Setup

Checked on 2026-05-17: AWS now describes a Free Plan with credits for up to 6 months for new customers, while EC2 docs still distinguish older accounts created before 2025-07-15 from newer accounts. Use the AWS console labels and billing page as the source of truth before leaving anything running.

1. Create an AWS account, then set a budget alert.
2. Launch one EC2 instance from the AWS console:
   - AMI: Ubuntu Server LTS
   - Instance type: choose the free-tier/free-plan eligible small instance shown by AWS, usually `t3.micro` or similar
   - Storage: 8-30 GiB is plenty
   - Security group: allow SSH `22` only from your IP; allow HTTPS `443` from anywhere; allow HTTP `80` from anywhere if using Caddy for certificates
3. Create or choose an SSH key pair and download the `.pem` file.
4. SSH to the machine:

```sh
chmod 400 ~/Downloads/YOUR_KEY.pem
ssh -i ~/Downloads/YOUR_KEY.pem ubuntu@YOUR_EC2_PUBLIC_DNS
```

Install the app:

```sh
sudo apt update
sudo apt install -y git python3-venv caddy sqlite3
git clone https://github.com/odcoda/ideaq.git ~/ideaq
cd ~/ideaq
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
sudo mkdir -p /var/lib/ideaq
sudo chown ubuntu:ubuntu /var/lib/ideaq
python3 -c 'import secrets; print(secrets.token_urlsafe(32))' > ~/ideaq-sync-token.txt
chmod 600 ~/ideaq-sync-token.txt
```

Create the systemd service:

```sh
TOKEN="$(cat ~/ideaq-sync-token.txt)"
sudo tee /etc/systemd/system/ideaq-sync.service >/dev/null <<EOF
[Unit]
Description=Idea Queue sync server
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/ideaq
Environment=IDEAQ_SERVER_DB=/var/lib/ideaq/ideaq-sync.sqlite3
Environment=IDEAQ_SYNC_TOKEN=$TOKEN
ExecStart=/home/ubuntu/ideaq/.venv/bin/gunicorn -w 1 -b 127.0.0.1:8050 'server.app:create_app()'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now ideaq-sync
sudo systemctl status ideaq-sync
```

If you have a domain, point an `A` record like `sync.example.com` to the EC2 public IP and let Caddy handle HTTPS:

```sh
sudo tee /etc/caddy/Caddyfile >/dev/null <<EOF
sync.example.com {
    reverse_proxy 127.0.0.1:8050
}
EOF
sudo systemctl reload caddy
```

Then test:

```sh
curl -H "Authorization: Bearer $(cat ~/ideaq-sync-token.txt)" \
  https://sync.example.com/v1/stores/default/snapshot
```

Use these client settings:

- Server URL: `https://sync.example.com`
- Store ID: `default`
- Bearer token: contents of `~/ideaq-sync-token.txt`

The iOS app should use HTTPS. The web dashboard can use HTTP for local testing, but HTTPS is the right default once the server is reachable from the internet.

## Backups

Back up the SQLite file regularly:

```sh
sudo mkdir -p /var/lib/ideaq/backups
sqlite3 /var/lib/ideaq/ideaq-sync.sqlite3 \
  ".backup '/var/lib/ideaq/backups/ideaq-$(date -Iseconds).sqlite3'"
```

To restore, stop the service and copy the backup over `/var/lib/ideaq/ideaq-sync.sqlite3`.

## Alternatives

- AWS EC2: best fit for this implementation because a tiny VM plus SQLite is simple and persistent. AWS Free Tier details changed for new accounts after 2025-07-15, so watch credits and budgets.
- A cheap VPS: often simpler than AWS if free is not required. You get one server, one monthly bill, SSH, and persistent disk.
- Render: has free web services, but free service filesystems are ephemeral; SQLite data can disappear on restart/redeploy. Free Postgres exists but expires after 30 days, so it is not a good long-term match without changing the storage backend.
- Fly.io: operationally nice for small apps with volumes, but their docs currently say there is no free account/free tier, only trials/allowances.
- Heroku: no longer has free dynos or free Postgres.

Official docs checked for the notes above:

- [AWS Free Tier](https://aws.amazon.com/free/)
- [AWS EC2 launch docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/LaunchingAndUsingInstances.html)
- [Render free instances](https://render.com/docs/free)
- [Fly.io cost management](https://fly.io/docs/about/cost-management/)
- [Heroku free resource deprecation](https://devcenter.heroku.com/changelog-items/2461)

