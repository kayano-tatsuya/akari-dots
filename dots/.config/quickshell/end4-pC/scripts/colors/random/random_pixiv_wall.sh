#!/usr/bin/env bash

# Random SFW wallpaper from Pixiv (mirrors random_konachan_wall.sh).
#
# Pixiv requires an account. You need a "refresh token" once; after that this
# script runs fully automatically.
#
# Getting a refresh token (do this once):
#   python3 scripts/colors/random/pixiv-auth.py get-url
#   -> log in, copy the "code" param from the redirect URL, then:
#   python3 scripts/colors/random/pixiv-auth.py exchange CODE
#   (saves the token to ~/.config/pixiv/refresh-token)
#
# Optional filters: create ~/.config/pixiv/config with any of these:
#   PIXIV_TAGS="landscape sunset"   # space-separated tags -> tag search
#                                  # (empty = use Pixiv's recommended feed)
#   PIXIV_SORT="date_desc"          # date_desc | date_asc | popular_desc | popular_asc
#   PIXIV_MIN_BOOKMARKS=1000        # only works with at least this many bookmarks
#   PIXIV_MIN_WIDTH=1920            # skip images smaller than this (avoid the
#   PIXIV_MIN_HEIGHT=1200           #   "Upscale?" prompt from switchwall)
#   PIXIV_ORIENTATION="landscape"   # landscape | portrait | square (empty = any)
#   PIXIV_NO_AI="true"              # skip AI-generated works
#
# SFW only: images with x_restrict == 0 (no R-18).
# Image is saved to ~/Pictures/Wallpapers and applied via switchwall.sh.

get_pictures_dir() {
    if command -v xdg-user-dir &> /dev/null; then
        xdg-user-dir PICTURES
        return
    fi

    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
    if [ -f "$config_file" ]; then
        local pictures_path
        pictures_path=$(source "$config_file" >/dev/null 2>&1; echo "$XDG_PICTURES_DIR")
        echo "${pictures_path/#\$HOME/$HOME}"
        return
    fi

    echo "$HOME/Pictures"
}

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
PICTURES_DIR=$(get_pictures_dir)
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

illogicalImpulseConfigPath="$HOME/.config/illogical-impulse/config.json"

# --- Pixiv constants (same public app credentials as pixiv-auth.py) ---
PIXIV_OAUTH="https://oauth.secure.pixiv.net/auth/token"
PIXIV_API="https://app-api.pixiv.net/v1"
CLIENT_ID="MOBrBDS8blbauoSck0ZfDbtuzpyT"
CLIENT_SECRET="lsACyCD94FhDUtGTXi3QzcFE2uU1hqtDaKeqrdwj"
USER_AGENT="PixivAndroidApp/5.0.234 (Android 11; Pixel 5)"
REFERER="https://www.pixiv.net/"

# --- Optional filters: ~/.config/pixiv/config (sourced if present) ---
PIXIV_TAGS=""
PIXIV_SORT="date_desc"
PIXIV_MIN_BOOKMARKS=""
PIXIV_MIN_WIDTH=""
PIXIV_MIN_HEIGHT=""
PIXIV_ORIENTATION=""
PIXIV_NO_AI="false"
PIXIV_CONFIG="$XDG_CONFIG_HOME/pixiv/config"
[ -f "$PIXIV_CONFIG" ] && . "$PIXIV_CONFIG"

# --- Refresh token: PIXIV_REFRESH_TOKEN env var, or saved by pixiv-auth.py ---
TOKEN_FILE="$XDG_CONFIG_HOME/pixiv/refresh-token"
REFRESH_TOKEN="${PIXIV_REFRESH_TOKEN:-}"
if [ -z "$REFRESH_TOKEN" ] && [ -f "$TOKEN_FILE" ]; then
    REFRESH_TOKEN=$(tr -d '[:space:]' < "$TOKEN_FILE")
fi
if [ -z "$REFRESH_TOKEN" ]; then
    echo "error: no Pixiv refresh token found."
    echo "Get one once with: python3 ${SCRIPT_DIR}/pixiv-auth.py get-url"
    exit 1
fi

# 1) Refresh token -> access token
tokenResp=$(curl -s -X POST "$PIXIV_OAUTH" \
    -H "User-Agent: $USER_AGENT" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET" \
    -d "grant_type=refresh_token" \
    -d "include_policy=true" \
    -d "refresh_token=$REFRESH_TOKEN")
accessToken=$(echo "$tokenResp" | jq -r '.access_token // empty')
if [ -z "$accessToken" ]; then
    echo "error: could not get a Pixiv access token (check the refresh token)."
    exit 1
fi

# 2) Fetch candidates: tag search, or the recommended feed when no tags given
if [ -n "$PIXIV_TAGS" ]; then
    offset=$((RANDOM % 450))
    echo "[pixiv] searching: $PIXIV_TAGS (sort=$PIXIV_SORT)" >&2
    resp=$(curl -s -G "$PIXIV_API/search/illust" \
        --data-urlencode "word=$PIXIV_TAGS" \
        -d "search_target=partial_match_for_tags" \
        -d "sort=$PIXIV_SORT" \
        -d "filter=for_ios" \
        -d "offset=$offset" \
        -H "Authorization: Bearer $accessToken" \
        -H "User-Agent: $USER_AGENT")
else
    echo "[pixiv] recommended feed" >&2
    resp=$(curl -s "$PIXIV_API/illust/recommended?content_type=illust&filter=for_ios" \
        -H "Authorization: Bearer $accessToken" \
        -H "User-Agent: $USER_AGENT")
fi

# 3) Pick one at random (SFW only + optional filters)
jqFilter='.illusts[] | select(.type == "illust" and .x_restrict == 0 and .sanity_level != 6'
if [ -n "$PIXIV_MIN_BOOKMARKS" ] && [ "$PIXIV_MIN_BOOKMARKS" -gt 0 ] 2>/dev/null; then
    jqFilter="$jqFilter and .total_bookmarks >= $PIXIV_MIN_BOOKMARKS"
fi
if [ -n "$PIXIV_MIN_WIDTH" ] && [ "$PIXIV_MIN_WIDTH" -gt 0 ] 2>/dev/null; then
    jqFilter="$jqFilter and .width >= $PIXIV_MIN_WIDTH"
fi
if [ -n "$PIXIV_MIN_HEIGHT" ] && [ "$PIXIV_MIN_HEIGHT" -gt 0 ] 2>/dev/null; then
    jqFilter="$jqFilter and .height >= $PIXIV_MIN_HEIGHT"
fi
if [ "${PIXIV_ORIENTATION:-}" = "landscape" ]; then
    jqFilter="$jqFilter and .width > .height"
elif [ "${PIXIV_ORIENTATION:-}" = "portrait" ]; then
    jqFilter="$jqFilter and .height > .width"
elif [ "${PIXIV_ORIENTATION:-}" = "square" ]; then
    jqFilter="$jqFilter and .width == .height"
fi
if [ "${PIXIV_NO_AI:-false}" = "true" ]; then
    jqFilter="$jqFilter and ((.ai_type // \"1\") != \"2\")"
fi
jqFilter="$jqFilter) | (.meta_single_page.original_image_url // (.meta_pages[0].image_urls.original // .meta_pages[0].image_urls.large) // .image_urls.large // empty)"

url=$(echo "$resp" | jq -r "$jqFilter" | sed '/^$/d' | shuf -n 1)

if [ -z "$url" ]; then
    echo "error: no usable SFW Pixiv illust found (try different tags/filters)"
    exit 1
fi

# 4) Download (Pixiv images need the Referer header)
mkdir -p "$PICTURES_DIR/Wallpapers"
ext=$(echo "$url" | awk -F. '{print $NF}' | tr -d '\r')
downloadPath="$PICTURES_DIR/Wallpapers/random_wallpaper_pixiv.$ext"
currentWallpaperPath=$(jq -r '.background.wallpaperPath' "$illogicalImpulseConfigPath")
if [ "$downloadPath" == "$currentWallpaperPath" ]; then
    downloadPath="$PICTURES_DIR/Wallpapers/random_wallpaper_pixiv-1.$ext"
fi
curl -s -L "$url" \
    -H "Referer: $REFERER" \
    -H "User-Agent: $USER_AGENT" \
    -o "$downloadPath"

# 5) Apply
"$SCRIPT_DIR/../switchwall.sh" --image "$downloadPath"