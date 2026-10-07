#!/usr/bin/env python3

"""
Report whether a directory tree still needs thumbnails generated.

Prints the number of image files that have NO valid thumbnail, then exits 0 if
that number is greater than zero ("work needed") or 1 if everything is already
valid ("nothing to do"). The QML caller uses the exit code to decide whether to
spawn the generator at all, so a fully-cached folder costs one cheap process
instead of a full thumbnail run.

Validity is decided by GnomeDesktop's DesktopThumbnailFactory.lookup(), the
SAME primitive the generator uses to decide freshness. That means the check
cannot drift from the writer the way a hand-rolled reimplementation of the
Freedesktop cache-key scheme would -- and such a reimplementation previously
disagreed with the QML side on filenames containing '!' or "'", silently
breaking those wallpapers.

Uses only GnomeDesktop + stdlib. Shares the version fallback with thumbgen.py.
"""

import os
import sys

import gi

for _ns_version in ("4.0", "3.0"):
    try:
        gi.require_version("GnomeDesktop", _ns_version)
        break
    except ValueError:
        continue
else:
    # No GnomeDesktop at all: we cannot validate. Report "needs work" so the
    # caller still runs the generator (which falls back to ImageMagick) rather
    # than wrongly concluding the cache is complete.
    print("-1", file=sys.stderr)
    sys.exit(0)

from gi.repository import Gio, GLib, GnomeDesktop  # isort:skip

# Keep in sync with Images.validImageExtensions (Images.qml) and thumbgen.py.
IMG_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp", ".avif", ".bmp", ".tif", ".tiff", ".svg", ".gif"}

THUMBNAIL_SIZES = {
    "normal": GnomeDesktop.DesktopThumbnailSize.NORMAL,
    "large": GnomeDesktop.DesktopThumbnailSize.LARGE,
    "x-large": GnomeDesktop.DesktopThumbnailSize.XLARGE,
    "xx-large": GnomeDesktop.DesktopThumbnailSize.XXLARGE,
}


def iter_images(root: str, max_depth: int):
    """Yield image files under root, bounded to max_depth levels below it.

    max_depth <= 0 means unlimited. Callers gate recursion on the caller side;
    this is only a safety bound against pathological trees.
    """
    root = os.path.realpath(root)
    root_depth = root.rstrip(os.sep).count(os.sep)
    for dirpath, dirnames, filenames in os.walk(root):
        if max_depth > 0 and dirpath.rstrip(os.sep).count(os.sep) - root_depth >= max_depth:
            dirnames[:] = []  # do not descend further
        for name in filenames:
            if os.path.splitext(name)[1].lower() in IMG_SUFFIXES:
                yield os.path.join(dirpath, name)


def main() -> int:
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <dir> <size> [max_depth]", file=sys.stderr)
        return 2

    target = sys.argv[1]
    size = sys.argv[2]
    max_depth = int(sys.argv[3]) if len(sys.argv) > 3 else 0

    if not os.path.isdir(target):
        print(f"Not a directory: {target}", file=sys.stderr)
        return 2

    factory = GnomeDesktop.DesktopThumbnailFactory.new(THUMBNAIL_SIZES[size])

    needed = 0
    for path in iter_images(target, max_depth):
        real = os.path.realpath(path)
        try:
            mtime = int(os.path.getmtime(real))
        except OSError:
            continue
        uri = GLib.filename_to_uri(real, None)
        if factory.lookup(uri, mtime) is not None:
            continue  # already have a valid, fresh-enough thumbnail
        # Distinguish "no thumbnail" from "cannot be thumbnailed" so a
        # permanently-unsupported file does not force a regen on every visit.
        try:
            info = Gio.File.new_for_path(real).query_info(
                "standard::content-type", Gio.FileQueryInfoFlags.NONE, None
            )
            mime = info.get_content_type()
        except GLib.Error:
            mime = None
        if mime and not factory.can_thumbnail(uri, mime, mtime):
            continue  # unsupported; generating will not help
        needed += 1

    print(needed)
    return 0 if needed > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
