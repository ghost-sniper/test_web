#!/bin/sh
set -eu

invalid_port() {
    echo 'MOCK_PORT must be between 1 and 65535 and differ from the Nginx port 8080.' >&2
    exit 1
}

case "$MOCK_PORT" in
    ''|*[!0-9]*|??????*) invalid_port ;;
esac
[ "$MOCK_PORT" -gt 0 ] && [ "$MOCK_PORT" -le 65535 ] && [ "$MOCK_PORT" -ne 8080 ] || invalid_port
export MOCK_HOST=127.0.0.1

default_config=/var/lib/zig-mock/mock.json
if [ "$MOCK_CONFIG" = "$default_config" ] && [ ! -e "$MOCK_CONFIG" ]; then
    mkdir -p "$(dirname "$MOCK_CONFIG")"
    cp /usr/local/share/zig-mock/mock.json "$MOCK_CONFIG"
fi

envsubst '${MOCK_PORT}' </etc/nginx/templates/mock.conf.template >/etc/nginx/conf.d/default.conf
nginx -t

mock_pid=
nginx_pid=
stop_services() {
    trap '' TERM INT QUIT
    if [ -n "$nginx_pid" ]; then
        kill -QUIT "$nginx_pid" 2>/dev/null || true
        wait "$nginx_pid" || true
    fi
    if [ -n "$mock_pid" ]; then
        kill -TERM "$mock_pid" 2>/dev/null || true
        wait "$mock_pid" || true
    fi
}
trap stop_services EXIT
trap 'exit 0' TERM INT QUIT

zig-mock &
mock_pid=$!
nginx -g 'daemon off;' &
nginx_pid=$!

while kill -0 "$mock_pid" 2>/dev/null && kill -0 "$nginx_pid" 2>/dev/null; do
    sleep 1
done

echo 'Nginx or Zig Mock exited. Stopping the container.' >&2
exit 1
