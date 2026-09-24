#!/usr/bin/env bash
# Read or toggle PIXIV_ALLOW_NSFW in the Pixiv filter config, backing the
# "Random: Pixiv NSFW" switch in the wallpaper settings.
#
# Usage: pixiv_nsfw.sh status | on | off
#   status   -> prints 1 if NSFW is allowed (PIXIV_ALLOW_NSFW="true"), else 0
#   on / off -> writes the flag, then prints the new status
#
# The same ~/.config/pixiv/config file is sourced by random_pixiv_wall.sh,
# so this stays the single source of truth (no config.json duplication).

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
PIXIV_CONFIG="$XDG_CONFIG_HOME/pixiv/config"

get_value() {
    [ -f "$PIXIV_CONFIG" ] || return
    sed -n 's|^PIXIV_ALLOW_NSFW=||p' "$PIXIV_CONFIG" \
        | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" \
        | tail -n 1
}

status() {
    [ "$(get_value)" = "true" ] && echo 1 || echo 0
}

set_value() {
    local value="$1"
    mkdir -p "$(dirname "$PIXIV_CONFIG")"
    if [ -f "$PIXIV_CONFIG" ] && grep -q '^PIXIV_ALLOW_NSFW=' "$PIXIV_CONFIG"; then
        sed -i "s|^PIXIV_ALLOW_NSFW=.*|PIXIV_ALLOW_NSFW=\"$value\"|" "$PIXIV_CONFIG"
    else
        printf 'PIXIV_ALLOW_NSFW="%s"\n' "$value" >> "$PIXIV_CONFIG"
    fi
    # keep a trailing newline so later appends stay on their own line
    [ -n "$(tail -c 1 "$PIXIV_CONFIG")" ] && printf '\n' >> "$PIXIV_CONFIG"
    status
}

case "${1:-}" in
    on|1|true) set_value true ;;
    off|0|false) set_value false ;;
    status|*) status ;;
esac