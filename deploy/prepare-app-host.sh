#!/bin/sh
set -eu
test "$(id -u)" = 0
if ! getent passwd moneytrack >/dev/null; then
  if getent passwd 10100 >/dev/null; then
    echo "UID 10100 is already allocated; review before provisioning." >&2
    exit 1
  fi
  if ! getent group moneytrack >/dev/null; then
    groupadd --gid 10100 moneytrack
  fi
  test "$(getent group moneytrack | cut -d: -f3)" = 10100
  useradd --system --uid 10100 --gid moneytrack --no-create-home --home-dir /var/lib/moneytrack --shell /usr/sbin/nologin moneytrack
fi
test "$(id -u moneytrack)" = 10100
test "$(id -g moneytrack)" = 10100
install -d -m 0755 /opt/moneytrack
install -d -m 0700 /etc/moneytrack
install -d -m 0700 -o moneytrack -g moneytrack /var/lib/moneytrack /var/backups/moneytrack
install -d -m 0755 -o paul -g paul /srv/moneytrack
if ! test -f /etc/moneytrack/moneytrack.env; then
  umask 077
  {
    printf 'PHX_HOST=app.example.invalid\nPHX_BIND_IP=192.0.2.10\nPORT=4018\n'
    printf 'DATABASE_PATH=/data/moneytrack.sqlite3\nPHX_SERVER=true\nSECRET_KEY_BASE='
    openssl rand -base64 64 | tr -d '\n'
    printf '\n'
  } > /etc/moneytrack/moneytrack.env
fi
chmod 0600 /etc/moneytrack/moneytrack.env
echo "MoneyTrack directories and private runtime environment prepared."
