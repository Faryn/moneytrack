# Private deployment configuration

The application VM runs one Phoenix/SQLite release. An external nginx host terminates HTTPS and forwards over Tailscale. The public deployment is verified, but its real hostname, SSH aliases, and addresses are intentionally excluded from tracked source and Git history.

## Local settings

Copy `local.example.json` to ignored `local.json` and enter the actual host settings there. Examples use reserved documentation addresses and are not runnable deployment targets. The existing checkout already has private settings populated.

```sh
python3 deploy/render.py
```

This produces host-specific files in ignored `deploy/local/`. Output elsewhere inside the repository is rejected. Generated files are mode 0600. Never commit the JSON settings or rendered files. The renderer validates DNS/SSH/address fields before substitution.

Use the tracked Compose file, backup command, and systemd units alongside the rendered firewall script. Run rendered `prepare-host.sh` as root on the application VM once. It creates UID/GID 10100, persistent storage, and a protected stable runtime secret, preserving an existing database/secret on later runs.

| Location on application VM | Purpose |
| --- | --- |
| `/srv/moneytrack/source` | Build source, separate from runtime data |
| `/opt/moneytrack` | Compose, rendered firewall, backup command |
| `/etc/moneytrack/moneytrack.env` | Root-only runtime settings and secret |
| `/var/lib/moneytrack` | SQLite database and WAL/SHM sidecars |
| `/var/backups/moneytrack` | Verified, closed SQLite snapshots |

## Application default

The iOS target loads `ios/Configuration/App.xcconfig`, which optionally includes ignored `Local.xcconfig`. Set `MONEYTRACK_SERVER_URL` there; see the tracked example for escaping URL slashes in xcconfig syntax. Both Debug and Release builds embed that configured URL as `MoneyTrackDefaultServerURL`. New sign-ins use it automatically. Existing credentials and pending changes stay associated with their original server/account.

Debug builds allow an explicit Development Server override. UI tests use only `MONEYTRACK_TEST_SERVER`; a missing/invalid test setting leaves the server unset rather than contacting the real instance.

## Build and service management

Build `server/Dockerfile` on the Linux application VM using its pinned image digests:

```sh
docker build --build-arg VCS_REF=YOUR_COMMIT -t moneytrack:prepared /srv/moneytrack/source/server
```

Install the tracked Compose/backup files and rendered firewall into `/opt/moneytrack`, and service/timer units into `/etc/systemd/system`. Validate units before starting them. The firewall service runs before the application, limits only its listener, and is reapplied on Tailscale restart. systemd supervises the container; Docker does not independently restart it ahead of the firewall.

```sh
sudo systemd-analyze verify /etc/systemd/system/moneytrack*.service /etc/systemd/system/moneytrack-backup.timer
sudo systemctl daemon-reload
sudo systemctl enable --now moneytrack-firewall.service
sudo docker compose -f /opt/moneytrack/compose.yaml run --rm --no-deps web /app/bin/moneytrack eval 'MoneyTrack.Release.migrate()'
sudo systemctl enable --now moneytrack.service
sudo systemctl start moneytrack-backup.service
sudo systemctl enable --now moneytrack-backup.timer
```

Create real accounts deliberately, with a password prompt and SSH stdin:

```sh
python3 deploy/local/create-user USERNAME
```

No default accounts are created by installation. Passwords stay out of command arguments and Git.

## nginx and TLS

Copy rendered `activate-public.sh` and `nginx-moneytrack.conf` together to a private staging directory on the proxy host. Invoke the script with sudo there. It checks the private backend, obtains a certificate using the existing Certbot account, validates nginx before reload, and checks public HTTPS separately over IPv4 and IPv6. A failure restores the previous site configuration. An HTTP-only ACME challenge remains available for renewals without exposing plaintext login. The certificate-specific reload hook and Certbot renewal timer are active.

The rendered IPv6 listener must match the proxy's existing explicit address. A wildcard IPv6 listener belongs to a different virtual-server group on this deployment. Readiness retries allow nginx's new workers to start before activation is declared successful.

## Updates and recovery

Create a verified backup before migrations, retain the previous image tag, stop the application for the migration window, migrate using the new image, and verify health/access after starting it. The release also applies pending migrations on startup. Do not automatically downgrade a database when rolling back an image.

Backups use SQLite's online backup API and `quick_check`, then close the destination as a standalone snapshot. They are private local files with no automatic deletion policy. Off-VM copies and retention remain to be selected. Restore while the app is stopped, preserving the current database/sidecars and stable runtime secret.

## Verification and boundaries

Verified on 2026-11-02: Linux release build; all four migrations; disposable account creation; empty production accounts; restart recovery; database integrity; private-port source restrictions; and verified daily backup. Public HTTPS health passes on IPv4 and IPv6. Login cookies are Secure/HttpOnly, HSTS is present, HTTP redirects to HTTPS, unauthenticated API access returns 401, and LiveView upgrades with status 101. TLS 1.3, certificate renewal scheduling, and its reload hook are verified.

Production mail, password recovery, passkeys, and iOS distribution remain separate work. No remote deployment is changed by rendering or editing private local configuration.

## Checks

```sh
python3 -m unittest discover -s deploy -p 'test_*.py'
python3 scripts/check-private-config
```

The privacy check rejects tracked local settings and known private host values. This repository has no configured remote; earlier local host-bearing deployment commits were rewritten after an external private bundle backup. Host-specific files and backups remain outside tracked history.
