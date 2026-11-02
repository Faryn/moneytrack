# application host deployment

One Phoenix website/API release, SQLite, and an nginx HTTPS proxy over Tailscale. Hosting decision: [ADR 0015](../docs/adr/0015-app-host-deployment.md). Runtime files are outside this OneDrive checkout.

## Layout

| Location | Purpose |
| --- | --- |
| application host `192.0.2.10:4018` | Private Phoenix listener; source-restricted to the proxy and local checks |
| Proxy `192.0.2.20` | proxy-host.example.invalid nginx host; public hostname app.example.invalid |
| `/srv/moneytrack/source` | Build source on application host; not a runtime data directory |
| `/opt/moneytrack` | Compose, firewall, and backup commands |
| `/etc/moneytrack/moneytrack.env` | Root-only stable runtime configuration/secret |
| `/var/lib/moneytrack/moneytrack.sqlite3` | Persistent SQLite, with WAL/SHM alongside it |
| `/var/backups/moneytrack` | Verified closed SQLite snapshots; not off-VM copies |

Build with the pinned [official Elixir image](https://hub.docker.com/_/elixir/) and Debian runtime in `server/Dockerfile`. The image includes the Erlang VM and an application release, following [Phoenix releases](https://phoenix.hexdocs.pm/releases.html). Runtime memory is capped at 512 MiB, CPU at 1.5 cores, with two Erlang schedulers. Docker does not independently restart the container: systemd supervises it so the firewall is established first.

## Build and install

Run `deploy/prepare-app-host.sh` as root on application host once; it creates the dedicated account/directories and a secret without printing it. Repeating it preserves the existing secret/database. Source uploads must exclude `.env`, dependencies, build output, databases, and financial data. Build on application host, not macOS:

```sh
docker build --build-arg VCS_REF=YOUR_COMMIT -t moneytrack:prepared /srv/moneytrack/source/server
```

Install `compose.yaml`, `moneytrack-firewall`, and `backup.py` into `/opt/moneytrack`; install the `.service`/`.timer` files into `/etc/systemd/system`. The firewall script must be executable and root-owned. Verify units before activation:

```sh
sudo systemd-analyze verify /etc/systemd/system/moneytrack*.service /etc/systemd/system/moneytrack-backup.timer
sudo systemctl daemon-reload
sudo systemctl enable --now moneytrack-firewall.service
```

For an initial database, run migrations before starting the service:

```sh
sudo docker compose -f /opt/moneytrack/compose.yaml run --rm --no-deps web /app/bin/moneytrack eval 'MoneyTrack.Release.migrate()'
sudo systemctl enable --now moneytrack.service
sudo systemctl start moneytrack-backup.service
sudo systemctl enable --now moneytrack-backup.timer
```

Create an account from the local checkout when ready:

```sh
python3 deploy/create-user USERNAME
```

The helper prompts without echoing, sends the password through SSH stdin, and never places it in command arguments or Git. No account is created by installation.

## Check and operate

```sh
ssh app-host 'sudo -n systemctl is-active moneytrack.service moneytrack-backup.timer'
ssh app-host 'sudo -n docker compose -f /opt/moneytrack/compose.yaml ps'
ssh app-host 'sudo -n journalctl -u moneytrack.service -n 40 --no-pager'
```

From the nginx host, expect 200 and `{"status":"ok"}`:

```sh
curl --fail -H 'Host: app.example.invalid' -H 'X-Forwarded-Proto: https' http://192.0.2.10:4018/api/health
```

The public health route is a liveness check; migration, database integrity, login redirect/cookies, and denied unauthenticated API access must also be checked when deploying. Other tailnet clients should time out on port 4018. Do not weaken the firewall to make a direct laptop connection work; use an SSH tunnel or run checks on the trusted hosts.

## Public proxy activation

The repository's `nginx-moneytrack.conf` is a staged configuration, not an installed site. First point `app.example.invalid` to the public nginx host (including correct IPv6 if used). Obtain its certificate using that host's existing Certbot setup. Then install the site with sudo, run `nginx -t`, and reload nginx only after validation. The template expects a per-host Let's Encrypt certificate; adapt its paths if the host instead uses a wildcard certificate. Test HTTPS, secure cookies, browser login, LiveView WebSocket upgrades, and authenticated API access. No public signup is enabled.

The activation script and template are staged at `/home/paul/moneytrack-deploy` on the proxy host. Run this in your own terminal to enter the sudo password there:

```sh
ssh -t proxy-host.example.invalid 'sudo sh /home/paul/moneytrack-deploy/activate-public.sh'
```

It checks application host first, uses an HTTP-only ACME challenge without serving login over plaintext, reuses the existing Certbot account, validates nginx before each reload, and checks public HTTPS health separately over IPv4 and IPv6 with reload-readiness retries. An activation failure restores the previous site configuration. Renewal challenges remain available after HTTPS activation, with a certificate-specific nginx reload hook. The script stops for administrator action if Certbot requires account selection or new account registration.

This host's proxy-host.example.invalid sites use the explicit IPv6 HTTPS listener `[2001:db8::10]:443`. MoneyTrack must join that listener; a wildcard `[::]:443` belongs to a different virtual-server group and can serve another site's certificate on IPv6. The original activation attempt rolled back and left no MoneyTrack nginx site; its Certbot renewal record exists. The corrected template is staged for a sudo rerun.

## Updates, backup and recovery

Take a fresh verified backup before migrations. Tag the current image for rollback, build a new immutable revision tag, and stop the app for the migration window. Run migrations with the new image and start it; confirm health and access before retiring the prior image. Do not automatically roll back a database schema when changing images.

The timer uses the SQLite online backup API and `quick_check`, so copying the live main file without WAL is unnecessary. Snapshots are separate closed files, mode 0600, with no automatic retention deletion. For recovery, stop the app, preserve the current database and sidecars, restore a verified snapshot as the service user, and retain the same runtime secret. A backup on the same VM does not survive loss of that VM; off-VM storage remains to be selected.

Production mail delivery/polling stays disabled, so email verification and sharing invitations need a delivery provider before being used publicly. Optional passkeys, password recovery, and iOS distribution remain separate work.

## Verified preparation · 2026-11-02

The Linux production image builds on application host. All 90 server tests pass. All four migrations apply; an isolated disposable release also verifies account creation, while the production database remains empty of accounts. systemd supervision, container health, secure/HttpOnly cookies, and unauthenticated API rejection are verified over the proxy host’s actual Tailscale path. A regular tailnet client is blocked. The first online backup passes integrity validation and the daily timer is enabled. The release also checks/applies pending migrations at startup, so take a verified backup before replacing its image.

DNS now resolves app.example.invalid to `203.0.113.10` and `2001:db8::10`. The current SSH user on the nginx host cannot use sudo without a password, and root SSH access is unavailable. Public activation is not yet verified; the corrected activation script is staged and syntax-checked.
