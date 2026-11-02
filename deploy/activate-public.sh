#!/bin/sh
set -eu
test "$(id -u)" = 0
directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
target=/etc/nginx/conf.d/app.example.invalid.conf
lineage=/etc/letsencrypt/live/app.example.invalid

curl --fail --silent --show-error --max-time 10 \
  -H 'Host: app.example.invalid' -H 'X-Forwarded-Proto: https' \
  http://192.0.2.10:4018/api/health >/dev/null

working=$(mktemp -d /tmp/moneytrack-nginx.XXXXXX)
had_previous=false
finished=false
cleanup() {
  status=$?
  trap - EXIT
  if test "$finished" != true; then
    if test "$had_previous" = true; then
      cp -a "$working/original.conf" "$target"
    else
      rm -f "$target"
    fi
    if /usr/sbin/nginx -t; then systemctl reload nginx; fi
  fi
  rm -rf "$working"
  exit "$status"
}

if test -f "$target"; then
  if test "$(head -n 1 "$target")" != '# MoneyTrack managed site'; then
    echo "An unmanaged MoneyTrack site exists; review it before activation." >&2
    exit 1
  fi
  cp -a "$target" "$working/original.conf"
  had_previous=true
  install -d -m 0700 /var/backups/nginx-moneytrack
  cp -a "$target" "/var/backups/nginx-moneytrack/$(date -u +%Y%m%dT%H%M%SZ).conf"
fi
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

install -d -m 0755 /var/www/letsencrypt
if ! test -f "$lineage/fullchain.pem" || ! test -f "$lineage/privkey.pem"; then
  # Serve only the certificate challenge over HTTP, never plaintext login.
  cat > "$target" <<'NGINX'
# MoneyTrack managed site
server {
    listen 80;
    listen [::]:80;
    server_name app.example.invalid;
    location /.well-known/acme-challenge/ { root /var/www/letsencrypt; }
    location / { return 503; }
}
NGINX
  chmod 0644 "$target"
  /usr/sbin/nginx -t
  systemctl reload nginx
  # Reuse this host's existing Certbot account. Do not register a new account
  # or accept new account terms without an administrator's intervention.
  certbot certonly --webroot --webroot-path /var/www/letsencrypt \
    --cert-name app.example.invalid -d app.example.invalid --non-interactive
fi

install -m 0644 "$directory/nginx-moneytrack.conf" "$target"
/usr/sbin/nginx -t
systemctl reload nginx
install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/moneytrack-nginx-reload <<'HOOK'
#!/bin/sh
set -eu
test "${RENEWED_LINEAGE:-}" = /etc/letsencrypt/live/app.example.invalid || exit 0
/usr/sbin/nginx -t
systemctl reload nginx
HOOK
chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/moneytrack-nginx-reload
curl --fail --silent --show-error --max-time 15 https://app.example.invalid/api/health
finished=true
printf '\nMoneyTrack HTTPS site activated.\n'
