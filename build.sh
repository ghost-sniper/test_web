#!/usr/bin/env bash
set -euo pipefail

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd -- "$project_root"
manifest="scripts/zig-toolchain.txt"
[[ -f build.zig && -f build.zig.zon && -f "$manifest" ]] || die "Project build files are missing."
read -r version < "$manifest"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid pinned Zig version."

matches_version() {
    local installed
    installed="$("$1" version 2>/dev/null)" && [[ "${installed%$'\r'}" == "$version" ]]
}

zig_bin="$(command -v zig || true)"
if [[ -z "$zig_bin" ]] || ! matches_version "$zig_bin"; then
    case "$(uname -s)" in
        Linux) os=linux ;;
        Darwin) os=macos ;;
        MINGW*|MSYS*|CYGWIN*) os=windows ;;
        *) die "No automatic download for this OS. Install Zig $version and add it to PATH." ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64) arch=x86_64 ;;
        aarch64|arm64) arch=aarch64 ;;
        i?86|x86) arch=x86 ;;
        *) die "No automatic download for this CPU. Install Zig $version and add it to PATH." ;;
    esac

    platform="$arch-$os"
    package="zig-$platform-$version"
    suffix=tar.xz
    executable=zig
    if [[ "$os" == windows ]]; then
        suffix=zip
        executable=zig.exe
    fi
    cache="$project_root/.zig-cache/toolchains"
    zig_bin="$cache/$package/$executable"

    if [[ ! -x "$zig_bin" ]] || ! matches_version "$zig_bin"; then
        expected=""
        while read -r entry checksum; do
            if [[ "$entry" == "$platform" ]]; then
                expected="$checksum"
                break
            fi
        done < "$manifest"
        [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || die "No pinned Zig archive for $platform."
        command -v curl >/dev/null || die "Install curl to download Zig $version."
        if command -v sha256sum >/dev/null; then
            checksum_cmd=(sha256sum)
        elif command -v shasum >/dev/null; then
            checksum_cmd=(shasum -a 256)
        else
            die "Install sha256sum or shasum to verify the Zig archive."
        fi
        if [[ "$suffix" == zip ]]; then
            command -v unzip >/dev/null || die "Install unzip to extract the Zig archive."
        else
            command -v tar >/dev/null || die "Install tar with xz support to extract the Zig archive."
        fi

        mkdir -p -- "$cache"
        cache="$(cd -- "$cache" && pwd -P)"
        [[ "$cache" == "$project_root/"* ]] || die "Toolchain cache must be inside the project."
        [[ ! -e "$cache/$package" ]] || die "Invalid cached toolchain: $cache/$package. Remove it and retry."
        stage="$(mktemp -d "$cache/.zig-download.XXXXXXXX")"
        [[ "$(cd -- "$stage" && pwd -P)" == "$cache"/.zig-download.* ]] || die "Unexpected staging directory."
        trap 'rm -rf -- "$stage"' EXIT
        archive="$stage/$package.$suffix"
        printf 'Downloading Zig %s for %s...\n' "$version" "$platform"
        curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --retry 2 \
            --connect-timeout 15 --max-time 300 \
            --output "$archive" "https://ziglang.org/download/$version/$package.$suffix" \
            || die "Could not download Zig $version."
        actual="$("${checksum_cmd[@]}" "$archive")"
        [[ "${actual%%[[:space:]]*}" == "$expected" ]] || die "Zig archive SHA-256 mismatch."
        if [[ "$suffix" == zip ]]; then
            unzip -q "$archive" -d "$stage"
        else
            tar -xJf "$archive" -C "$stage" || die "Could not extract the Zig archive. Check that tar supports xz."
        fi
        matches_version "$stage/$package/$executable" || die "Downloaded compiler failed its version check."
        mv -- "$stage/$package" "$cache/" || matches_version "$zig_bin" || die "Could not cache Zig."
    fi
fi

printf 'Using Zig %s: %s\n' "$version" "$zig_bin"
printf 'Checking project dependencies...\n'
"$zig_bin" build --fetch || die "Dependency check failed. Check the fetch error above."
printf 'Building with the default optimization level...\n'
"$zig_bin" build
