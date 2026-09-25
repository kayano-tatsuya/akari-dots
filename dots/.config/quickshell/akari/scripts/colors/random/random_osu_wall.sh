#!/usr/bin/env bash

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

mkdir -p "$PICTURES_DIR/Wallpapers"

response=$(curl "https://osu.ppy.sh/api/v2/seasonal-backgrounds")
images=$(echo "$response" | jq '.backgrounds | length' -r);
randomIndex=$((RANDOM % images));
link=$(echo "$response" | jq ".backgrounds[$randomIndex].url" -r)
ext=$(echo "$link" | awk -F. '{print $NF}')
# Unique filename each pull so the preview above the random buttons stays
# fresh (in-place overwrites keep stale thumbnails, which are keyed by path).
illogicalImpulseConfigPath="$HOME/.config/akari/config.json"
downloadPath="$PICTURES_DIR/Wallpapers/random_wallpaper_osu_$(date +%s).$ext"
curl "$link" -o "$downloadPath"

if [ ! -s "$downloadPath" ]; then
    echo "error: osu download failed"
    exit 1
fi

"$SCRIPT_DIR/../switchwall.sh" --image "$downloadPath"

# Keep the folder tidy: drop older random osu pulls (never the current or
# lock wallpaper).
prune_old_wallpapers() {
    local current lock
    current=$(jq -r '.background.wallpaperPath // empty' "$illogicalImpulseConfigPath" 2>/dev/null)
    lock=$(jq -r '.background.lockWall // empty' "$illogicalImpulseConfigPath" 2>/dev/null)
    local f k skip
    for f in "$PICTURES_DIR"/Wallpapers/random_wallpaper_osu_*; do
        [ -f "$f" ] || continue
        skip=0
        for k in "$current" "$lock"; do
            [ "$f" == "$k" ] && skip=1
        done
        [ "$skip" -eq 0 ] && rm -f "$f"
    done
}

prune_old_wallpapers
