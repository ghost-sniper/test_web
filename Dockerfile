# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM debian:bookworm-slim AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/zig-toolchain.txt /tmp/zig-toolchain.txt
ARG BUILDARCH
RUN set -eu; \
    case "$BUILDARCH" in \
        amd64) arch=x86_64 ;; \
        arm64) arch=aarch64 ;; \
        *) echo "Unsupported Zig build architecture: $BUILDARCH" >&2; exit 1 ;; \
    esac; \
    read -r version < /tmp/zig-toolchain.txt; \
    checksum="$(awk -v platform="$arch-linux" '$1 == platform { print $2 }' /tmp/zig-toolchain.txt)"; \
    archive="zig-$arch-linux-$version.tar.xz"; \
    curl --fail --silent --show-error --location --retry 2 \
        --proto '=https' --proto-redir '=https' \
        "https://ziglang.org/download/$version/$archive" -o "/tmp/$archive"; \
    printf '%s  %s\n' "$checksum" "/tmp/$archive" | sha256sum -c -; \
    mkdir /opt/zig; \
    tar -xJf "/tmp/$archive" --strip-components=1 -C /opt/zig; \
    rm "/tmp/$archive"

WORKDIR /src
COPY build.zig build.zig.zon ./
COPY src/ src/
ARG TARGETARCH
RUN set -eu; \
    case "$TARGETARCH" in \
        amd64) target=x86_64-linux-musl ;; \
        arm64) target=aarch64-linux-musl ;; \
        *) echo "Unsupported runtime architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    /opt/zig/zig build -Dtarget="$target" -Doptimize=ReleaseSafe --prefix /out

FROM nginx:stable-alpine

RUN apk add --no-cache tini
COPY --from=build /out/bin/test_web /usr/local/bin/zig-mock
COPY config/mock.json /usr/local/share/zig-mock/mock.json
COPY deploy/docker/nginx.conf.template /etc/nginx/templates/mock.conf.template
COPY --chmod=755 deploy/docker/start-mock.sh /usr/local/bin/start-mock

ENV MOCK_PORT=9080 \
    MOCK_CONFIG=/var/lib/zig-mock/mock.json
EXPOSE 8080
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/local/bin/start-mock"]
