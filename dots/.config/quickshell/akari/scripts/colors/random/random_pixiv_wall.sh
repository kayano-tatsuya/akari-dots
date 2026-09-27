#!/usr/bin/env bash

# Random wallpaper from Pixiv (mirrors random_konachan_wall.sh).
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
#   PIXIV_ALLOW_NSFW="true"         # allow R-18 (default: SFW only)
#   PIXIV_WALLPAPER_TAG="true"      # restrict pulls to works tagged as
#   PIXIV_WALLPAPER_TAG_VALUE="壁紙" #   wallpapers (default tag: 壁紙)
#                                  # (see the wallpaper-tag switch in settings)
#
# SFW by default (x_restrict == 0, sanity_level != 6). With
# PIXIV_ALLOW_NSFW="true" the R-18 filter is removed and the API is queried
# with filter=for_android so R-18 works actually come back in the results.
# Note: the recommended feed is SFW-only even then, so a no-tags NSFW pick
# falls back to a random R-18 ranking (day/week/male/female). Tag
# searches include R-18 directly.
# Each pick is saved to a unique file
# (~/Pictures/Wallpapers/random_wallpaper_pixiv_<ts>.<ext>), avoids re-picking
# recently used illusts (ids kept in
# $XDG_STATE_HOME/quickshell/pixiv-recent-ids), and is applied via
# switchwall.sh. Older random pixiv pulls are pruned automatically (the
# current and lock wallpapers are kept). R-18/R-18G picks instead go into the
# "Homework shelf" (~/Pictures/homework/🌶️), which is never pruned.

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

QUICKSHELL_CONFIG_NAME="akari"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
PICTURES_DIR=$(get_pictures_dir)
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

illogicalImpulseConfigPath="$HOME/.config/akari/config.json"

# State file: illust ids picked recently, so consecutive pulls skip them and
# don't keep re-downloading the same works a few clicks later.
PIXIV_RECENT_FILE="$STATE_DIR/pixiv-recent-ids"
mkdir -p "$STATE_DIR"

# --- Pixiv constants (same public app credentials as pixiv-auth.py) ---
PIXIV_OAUTH="https://oauth.secure.pixiv.net/auth/token"
PIXIV_API="https://app-api.pixiv.net/v1"
DEFAULT_CLIENT_ID="MOBrBDS8blbauoSck0ZfDbtuzpyT"
DEFAULT_CLIENT_SECRET="lsACyCD94FhDUtGTXi3QzcFE2uU1hqtDaKeqrdwj"
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
PIXIV_ALLOW_NSFW="false"
PIXIV_WALLPAPER_TAG="false"
PIXIV_WALLPAPER_TAG_VALUE="壁紙"
PIXIV_CONFIG="$XDG_CONFIG_HOME/pixiv/config"
[ -f "$PIXIV_CONFIG" ] && . "$PIXIV_CONFIG"

# Credentials: the config file wins, the built-in pair is the fallback. :- treats
# a blank override as unset, so a half-edited line can't post an empty client_id.
# Same key names and same precedence as pixiv-auth.py and OnlineWallpapers.qml.
CLIENT_ID="${PIXIV_CLIENT_ID:-$DEFAULT_CLIENT_ID}"
CLIENT_SECRET="${PIXIV_CLIENT_SECRET:-$DEFAULT_CLIENT_SECRET}"

# for_ios excludes R-18 from the API results, for_android includes it.
PIXIV_FILTER="for_ios"
[ "${PIXIV_ALLOW_NSFW:-false}" = "true" ] && PIXIV_FILTER="for_android"

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
#    When the wallpaper-tag toggle is on, add the wallpaper tag to any user
#    tags (or use just that tag), so pulls favor wallpaper-oriented works.
search_tags="$PIXIV_TAGS"
if [ "${PIXIV_WALLPAPER_TAG:-false}" = "true" ]; then
    search_tags="${search_tags:+$search_tags }${PIXIV_WALLPAPER_TAG_VALUE:-壁紙}"
    echo "[pixiv] wallpaper tag: ${PIXIV_WALLPAPER_TAG_VALUE:-壁紙}" >&2
fi

echo "[pixiv] safety: $([ "${PIXIV_ALLOW_NSFW:-false}" = "true" ] && echo nsfw || echo sfw)" >&2
if [ -n "$search_tags" ]; then
    offset=$((RANDOM % 450))
    echo "[pixiv] searching: $search_tags (sort=$PIXIV_SORT)" >&2
    resp=$(curl -s -G "$PIXIV_API/search/illust" \
        --data-urlencode "word=$search_tags" \
        -d "search_target=partial_match_for_tags" \
        -d "sort=$PIXIV_SORT" \
        -d "filter=$PIXIV_FILTER" \
        -d "offset=$offset" \
        -H "Authorization: Bearer $accessToken" \
        -H "User-Agent: $USER_AGENT")
elif [ "${PIXIV_ALLOW_NSFW:-false}" = "true" ]; then
    # The recommended feed is SFW-only even with filter=for_android, so use
    # R-18 rankings for a random NSFW pick when no tags are given. Randomize
    # the ranking mode (daily/weekly/male/female) so the pool is not just
    # today's top page, and retry a couple of times if a page comes back empty.
    r18Modes=(day_r18 week_r18 day_male_r18 day_female_r18)
    for _ in 1 2; do
        mode=${r18Modes[$((RANDOM % ${#r18Modes[@]}))]}
        offset=$(( (RANDOM % 2) * 50 + 1 ))
        resp=$(curl -s -G "$PIXIV_API/illust/ranking" \
            -d "mode=$mode" \
            -d "filter=$PIXIV_FILTER" \
            -d "offset=$offset" \
            -H "Authorization: Bearer $accessToken" \
            -H "User-Agent: $USER_AGENT")
        echo "[pixiv] R-18 ranking: $mode (offset=$offset)" >&2
        n=$(echo "$resp" | jq '.illusts | length // 0' 2>/dev/null)
        [ "${n:-0}" -gt 0 ] && break
    done
else
    echo "[pixiv] recommended feed" >&2
    resp=$(curl -s "$PIXIV_API/illust/recommended?content_type=illust&filter=$PIXIV_FILTER" \
        -H "Authorization: Bearer $accessToken" \
        -H "User-Agent: $USER_AGENT")
fi

# 3) Pick one at random (optional filters; SFW enforcement unless NSFW allowed).
#    Skip illusts picked recently and emit "id<TAB>url" so the pick can be
#    recorded for the next run.
usedJson=$(jq -sR 'split("\n") | map(select(length > 0))' "$PIXIV_RECENT_FILE" 2>/dev/null)
[ -z "$usedJson" ] && usedJson="[]"

jqFilter='.illusts[] | select(.type == "illust"'
if [ "${PIXIV_ALLOW_NSFW:-false}" != "true" ]; then
    jqFilter="$jqFilter and .x_restrict == 0 and .sanity_level != 6"
fi
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
jqFilter="$jqFilter and ((.id | tostring) | IN(\$used[]) | not)"
jqFilter="$jqFilter) | [(.id | tostring), (.meta_single_page.original_image_url // (.meta_pages[0].image_urls.original // .meta_pages[0].image_urls.large) // .image_urls.large // empty), (.x_restrict // 0 | tostring), (.sanity_level // 0 | tostring)] | @tsv"

line=$(echo "$resp" | jq -r --argjson used "$usedJson" "$jqFilter" | sed '/^[[:space:]]*$/d' | shuf -n 1)
if [ -z "$line" ]; then
    echo "error: no usable Pixiv illust found (try different tags/filters)"
    exit 1
fi
id=$(echo "$line" | cut -f1)
url=$(echo "$line" | cut -f2)
if [ -z "$url" ]; then
    echo "error: no usable Pixiv illust found (try different tags/filters)"
    exit 1
fi

# A work is R-18/R-18G when x_restrict != 0 or sanity_level == 6; only such
# picks count as the "actual NSFW pull" (SFW works pulled while NSFW mode is
# on still stay in ~/Pictures/Wallpapers, never in the homework shelf).
xRestrict=$(echo "$line" | cut -f3)
sanityLevel=$(echo "$line" | cut -f4)
isNsfw=false
if [ "${PIXIV_ALLOW_NSFW:-false}" = "true" ] && { [ "$xRestrict" != "0" ] || [ "$sanityLevel" = "6" ]; }; then
    isNsfw=true
fi

# 4) Download (Pixiv images need the Referer header). Save to a unique
#    filename so the preview above the random buttons gets a fresh thumbnail
#    (in-place overwrites keep stale previews because thumbnails are keyed by
#    the file path).
prune_old_wallpapers() {
    local current lock
    current=$(jq -r '.background.wallpaperPath // empty' "$illogicalImpulseConfigPath" 2>/dev/null)
    lock=$(jq -r '.background.lockWall // empty' "$illogicalImpulseConfigPath" 2>/dev/null)
    local f k skip
    for f in "$PICTURES_DIR"/Wallpapers/random_wallpaper_pixiv_*; do
        [ -f "$f" ] || continue
        skip=0
        for k in "$current" "$lock"; do
            [ "$f" == "$k" ] && skip=1
        done
        [ "$skip" -eq 0 ] && rm -f "$f"
    done
}

mkdir -p "$PICTURES_DIR/Wallpapers"
ext=$(echo "$url" | awk -F. '{print $NF}' | tr -d '\r')
if [ "$isNsfw" = "true" ]; then
    # Actual R-18/R-18G pull -> the Homework shelf. The shelf is a trophy
    # case: it is never pruned (unlike ~/Pictures/Wallpapers). Only this
    # branch may create homework/🌶️ (never for SFW pulls, never elsewhere).
    homeworkDir="$PICTURES_DIR/homework/🌶️"
    mkdir -p "$homeworkDir"
    downloadPath="$homeworkDir/random_wallpaper_pixiv_$(date +%s).$ext"
    echo "[pixiv] R-18 -> homework shelf: $homeworkDir" >&2
else
    downloadPath="$PICTURES_DIR/Wallpapers/random_wallpaper_pixiv_$(date +%s).$ext"
fi
curl -s -L "$url" \
    -H "Referer: $REFERER" \
    -H "User-Agent: $USER_AGENT" \
    -o "$downloadPath"

if [ ! -s "$downloadPath" ]; then
    echo "error: download failed for $url"
    exit 1
fi

# Remember this pick so future pulls avoid an immediate repeat (~20 ids).
{ echo "$id"; head -n 19 "$PIXIV_RECENT_FILE" 2>/dev/null || true; } > "$PIXIV_RECENT_FILE.tmp" \
    && mv "$PIXIV_RECENT_FILE.tmp" "$PIXIV_RECENT_FILE"

# 5) Apply
"$SCRIPT_DIR/../switchwall.sh" --image "$downloadPath"

# 6) Keep ~/Pictures/Wallpapers tidy: drop older random pixiv pulls (never the
#    currently applied wallpaper or the lock wallpaper).
prune_old_wallpapers