# ADR 0015: application host backend with nginx over Tailscale

- Status: Accepted hosting direction; private deployment preparation
- Date: 2026-11-02

The user selected the local VM `app-host` for the Phoenix website/API and SQLite. Internet access will use nginx on `proxy-host.example.invalid`, linked to application host by Tailscale. The selected public hostname is `app.example.invalid`.

## Decision

- Package the existing single Phoenix application as an Elixir release in one Docker container. application host already runs Docker; no new database server, frontend service, or orchestration cluster is introduced.
- Pin the official Elixir 1.20.4/OTP 29 build image and matching Debian 13 runtime image by digest. Compile dependencies, assets, native SQLite/bcrypt libraries, and the release on application host's Linux x86_64 architecture.
- Bind Phoenix only to application host's Tailscale address `192.0.2.10:4018`. Use host networking to avoid Docker port-forwarding bypass of the host INPUT policy. A dedicated rule for this listener precedes Tailscale's generic accept rule and permits only the nginx host `192.0.2.20` and application host itself. Other services and firewall ports are untouched.
- systemd starts the firewall before the container and supervises restart behavior. Reapply listener protection on Tailscale restarts. The container runs as UID/GID 10100 with a read-only image, dropped capabilities, bounded memory/CPU/PIDs, and a temporary directory.
- Store SQLite and its WAL/SHM files at `/var/lib/moneytrack`, mounted as `/data`; never inside source, the image, or cloud-synced storage. Keep the stable server-generated secret in root-only `/etc/moneytrack/moneytrack.env`.
- Use SQLite's online backup API for daily verified local snapshots at `/var/backups/moneytrack`. Preserve the runtime secret separately for recovery. Off-VM copies and retention are not configured in this preparation.
- nginx terminates public HTTPS, sets the fixed public Host and HTTPS forwarding header, and forwards WebSocket traffic over Tailscale. Backend access is source-restricted because production trusts the proxy's HTTPS header. Keep the public domain in Phoenix's runtime URL/origin checks.
- Keep administrator-created accounts. Provide release migration and password-on-stdin account commands; create no default or synthetic production account.

## Current boundary

Preparation does not configure production email, passkeys, password recovery, or TestFlight. The public nginx configuration is staged for review. DNS for the chosen hostname and sudo access on the nginx host are needed before public activation; application host sudo access is available. The existing authorization and transport rules in [ADR 0008](0008-connected-accounts-and-transport.md) still apply.

See the [deployment runbook](../../deploy/README.md) and [Phoenix release documentation](https://phoenix.hexdocs.pm/releases.html).

## Public activation verified · 2026-11-02

The user installed the site and certificate with sudo. Public HTTPS health passes on IPv4 and IPv6; the login page, secure cookies, HSTS, HTTP redirect, unauthenticated API rejection, and LiveView WebSocket upgrade are verified. Certificate renewal scheduling and its nginx reload hook are active. The explicit host IPv6 listener is required. Accounts, mail delivery, recovery, passkeys, and iOS distribution remain separate work.
