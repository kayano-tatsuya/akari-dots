#!/usr/bin/env bash

# Generate thumbnails for files using ImageMagick, following Freedesktop spec
#
# This is the FALLBACK generator. The primary path is thumbgen-venv.sh
# (GnomeDesktop/gi), which is spec-correct and much better. This script only
# runs when the primary is unavailable. It is kept spec-valid too, so switching
# between the two does not invalidate the cache -- both write the same
# Thumb::MTime / Thumb::URI PNG metadata that DesktopThumbnailFactory.lookup()
# validates against.
#
# Usage:
#   ./generate-thumbnails-magick.sh --file <path>
#   ./generate-thumbnails-magick.sh --directory <path> [--recursive] [--max-depth N]

set -euo pipefail

# Thumbnail sizes mapping
get_thumbnail_size() {
    case "$1" in
        normal) echo 128 ;;
        large) echo 256 ;;
        x-large) echo 512 ;;
        xx-large) echo 1024 ;;
        *) echo 128 ;;
    esac
}

usage() {
    echo "Usage: $0 --file <path> | --directory <path> [--recursive] [--max-depth N]" >&2
    exit 1
}

# Percent-encode a path for use in a URI, but do not encode slashes.
# The unreserved set MUST match what the QML side uses to compute the cache
# key (ThumbnailImage.qml percent-encodes each path segment via
# encodeURIComponent). encodeURIComponent leaves these unescaped:
#   A-Z a-z 0-9 - _ . ! ~ * ' ( )
# Getting this wrong means a thumbnail is WRITTEN under a hash the UI never
# looks up -> permanently blank tile. The original class here omitted ! and ',
# which silently broke any wallpaper with an apostrophe or exclamation mark
# in its name (e.g. "it's-me.png", "wow!.jpg").
urlencode() {
    local str="$1"
    local encoded=""
    local c
    # Iterate BYTES, not characters. printf %X on a multibyte character yields
    # that character's code point, so a filename containing e.g. "ü" came out as
    # %FC (latin-1) instead of the %C3%BC that URI encoding requires. Forcing
    # the C locale makes ${#str} and substring extraction byte-wise, which is
    # exactly the UTF-8 percent-encoding we want.
    local LC_ALL=C
    for ((i=0; i<${#str}; i++)); do
        c="${str:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_!-]|/|'('|')'|'*'|"'") encoded+="$c" ;;
            *) printf -v hex '%%%02X' "'${c}'"; encoded+="$hex" ;;
        esac
    done
    printf '%s' "$encoded"
}

md5() {
    # Calculate md5 hash of the file's absolute path URI
    echo -n "$1" | md5sum | awk '{print $1}'
}

# Image extensions, in sync with Images.validImageExtensions (Images.qml) and
# thumbgen.py's IMG_SUFFIXES. Only these are worth thumbnailing; the original
# script tried every file in the directory, which on ~/Pictures meant burning
# CPU on 600+ screenshots that the picker never renders.
is_image() {
    case "${1,,}" in
        *.jpg|*.jpeg|*.png|*.webp|*.avif|*.bmp|*.tif|*.tiff|*.svg|*.gif) return 0 ;;
        *) return 1 ;;
    esac
}

# Worker: generate a single thumbnail. Runs in a background subshell.
generate_thumbnail() {
    local src="$1"
    local abs_path
    abs_path="$(realpath "$src")"
    # Skip multi-frame / video formats ImageMagick would mangle.
    case "${abs_path,,}" in
        *.mp4|*.webm|*.mkv|*.avi|*.mov) return ;;
    esac
    is_image "$abs_path" || return
    local encoded_path uri hash out
    encoded_path="$(urlencode "$abs_path")"
    uri="file://$encoded_path"
    hash="$(md5 "$uri")"
    out="$CACHE_DIR/$hash.png"
    mkdir -p "$CACHE_DIR"
    # Skip if a thumbnail already exists AND is newer than the source, so an
    # edited-in-place wallpaper actually gets refreshed. The original returned
    # on mere existence, so stale previews lived forever.
    if [ -f "$out" ] && [ "$out" -nt "$abs_path" ]; then
        return
    fi
    local mtime
    mtime="$(stat -c %Y "$abs_path")"
    # Embed Thumb::MTime / Thumb::URI so spec consumers (and the primary
    # generator's lookup()) accept this thumbnail.
    local tmp="$out.$$.tmp.png"
    # ImageMagick interprets "%" in a -set value as a percent-escape, so "%20"
    # is eaten as the unknown property "%2" and collapses to a bare "0". That
    # silently corrupted Thumb::URI for every path containing a space, which is
    # why all 13 thumbnails under "SAVED (NO OVERRIDES)" came out spec-invalid
    # and would still render as blank tiles. Doubling the percent is IM's own
    # escape for a literal one.
    local uri_escaped="${uri//%/%%}"
    if magick "$abs_path" -resize "${THUMBNAIL_SIZE}x${THUMBNAIL_SIZE}" \
        -define png:exclude-chunk=date,time \
        -set "Thumb::URI" "$uri_escaped" -set "Thumb::MTime" "$mtime" "$tmp" 2>/dev/null; then
        mv "$tmp" "$out"
    else
        rm -f "$tmp"
    fi
}

# Parse arguments
SIZE_NAME="normal"
MODE=""
TARGET=""
RECURSIVE=0
MAX_DEPTH=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --file|-f) MODE="file"; TARGET="$2"; shift 2 ;;
        --directory|-d) MODE="dir"; TARGET="$2"; shift 2 ;;
        --size|-s) SIZE_NAME="$2"; shift 2 ;;
        --recursive|-R) RECURSIVE=1; shift ;;
        --max-depth) MAX_DEPTH="$2"; shift 2 ;;
        *) usage ;;
    esac
    [[ -n "$MODE" ]] && break
done

THUMBNAIL_SIZE="$(get_thumbnail_size "$SIZE_NAME")"
CACHE_DIR="$HOME/.cache/thumbnails/$SIZE_NAME"

if [ -z "$MODE" ] || [ -z "$TARGET" ]; then
    usage
fi

# Bound the parallel fan-out. The original did `generate_thumbnail "$f" &` for
# every file with no limit -- fine for 20 wallpapers, but a recursive pass over
# ~/Pictures (650+ files) would fork-storm the box. Cap at 12 workers.
MAX_JOBS="${THUMBGEN_JOBS:-12}"
throttle() {
    while [ "$(jobs -rp | wc -l)" -ge "$MAX_JOBS" ]; do
        wait -n 2>/dev/null || sleep 0.05
    done
}

case "$MODE" in
    file)
        if [ ! -f "$TARGET" ]; then
            echo "File not found: $TARGET" >&2
            exit 2
        fi
        generate_thumbnail "$TARGET"
        ;;
    dir)
        if [ ! -d "$TARGET" ]; then
            echo "Directory not found: $TARGET" >&2
            exit 2
        fi
        if [ "$RECURSIVE" -eq 1 ]; then
            if [ "$MAX_DEPTH" -gt 0 ]; then
                FIND_ARGS=(find "$TARGET" -maxdepth "$MAX_DEPTH" -type f)
            else
                FIND_ARGS=(find "$TARGET" -type f)
            fi
        else
            FIND_ARGS=(find "$TARGET" -maxdepth 1 -type f)
        fi
        while IFS= read -r -d '' f; do
            throttle
            generate_thumbnail "$f" &
        done < <("${FIND_ARGS[@]}" -print0)
        wait
        ;;
    *)
        usage
        ;;
esac
