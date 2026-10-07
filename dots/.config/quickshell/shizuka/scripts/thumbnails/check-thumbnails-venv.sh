#!/usr/bin/env bash
# Run check-thumbnails.py inside the shell's Python virtualenv, where the
# GnomeDesktop typelib bindings live. Mirrors thumbgen-venv.sh, which does the
# same for thumbgen.py. The QML caller invokes this (not the .py directly)
# because `import gi` / GnomeDesktop are only available in that venv.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source $(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate
exec "$SCRIPT_DIR/check-thumbnails.py" "$@"
