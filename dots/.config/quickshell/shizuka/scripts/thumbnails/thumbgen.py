#!/usr/bin/env python3

# From https://github.com/difference-engine/thumbnail-generator-ubuntu (MIT License)
# Since the script is small and the maintainers seem inactive to accept my PR (#11) I decided to just copy it over.
# When it gets merged and the python package gets updated we can just use it

import os
import sys
from multiprocessing import Pool
from pathlib import Path
from typing import List, Union

import click
import gi
from loguru import logger
from tqdm import tqdm

# Prefer the 4.0 namespace, but fall back to 3.0.
#
# This hardcoded "4.0" is why the whole primary thumbnail path was dead: it
# raises ValueError and exits 1 on every invocation, so the caller's `||`
# fallback (ImageMagick) silently did 100% of the work instead. Distros that
# ship only libgnome-desktop 44.x -- Arch/CachyOS among them -- provide the
# GnomeDesktop-3.0 typelib and no 4.0 one at all. Upgrading to get 4.0 means a
# gnome-desktop 47+ partial system upgrade, which is wildly out of proportion
# for a wallpaper previewer.
#
# DesktopThumbnailFactory's API is identical in 3.0 and 4.0, so try 4.0 first
# (harmless where it exists, correct on future distros) and settle for 3.0.
for _ns_version in ("4.0", "3.0"):
    try:
        gi.require_version("GnomeDesktop", _ns_version)
        break
    except ValueError:
        continue
else:
    raise SystemExit(
        "GnomeDesktop typelib not found. Expected GnomeDesktop-3.0 or 4.0. "
        "On Arch install the 'gnome-desktop' package."
    )

from gi.repository import Gio, GnomeDesktop  # isort:skip

thumbnail_size_map = {
    "normal": GnomeDesktop.DesktopThumbnailSize.NORMAL,
    "large": GnomeDesktop.DesktopThumbnailSize.LARGE,
    "x-large": GnomeDesktop.DesktopThumbnailSize.XLARGE,
    "xx-large": GnomeDesktop.DesktopThumbnailSize.XXLARGE,
}

factory = None
logger.remove()
logger.add(sys.stdout, level="INFO")
logger.add("/tmp/thumbgen.log", level="DEBUG", rotation="100 MB")

def make_thumbnail(fpath: str) -> bool:
    mtime = os.path.getmtime(fpath)
    # Use Gio to determine the URI and mime type
    f = Gio.file_new_for_path(str(fpath))
    uri = f.get_uri()
    info = f.query_info("standard::content-type", Gio.FileQueryInfoFlags.NONE, None)
    mime_type = info.get_content_type()

    if factory.lookup(uri, mtime) is not None:
        logger.debug("FRESH       {}".format(uri))
        return False

    if not factory.can_thumbnail(uri, mime_type, mtime):
        logger.debug("UNSUPPORTED {}".format(uri))
        return False

    thumbnail = factory.generate_thumbnail(uri, mime_type)
    if thumbnail is None:
        logger.debug("ERROR       {}".format(uri))
        return False

    logger.debug("OK          {}".format(uri))
    factory.save_thumbnail(thumbnail, uri, mtime)
    return True


# thumbnail_folder swallows its own exceptions (loguru's @logger.catch), so it
# has to report failure through its return value. Upstream returned None, which
# the caller could not distinguish from success, and the process still exited 0
# -- so a total failure looked like a clean run. That matters because the QML
# caller relies on `primary || fallback`: with a 0 exit status the ImageMagick
# fallback never fired, and a broken primary produced blank tiles with no error
# anywhere. See Wallpapers.qml generateThumbnail().
_THUMBNAIL_FOLDER_FAILED = -1


@logger.catch(default=_THUMBNAIL_FOLDER_FAILED)
def thumbnail_folder(*, dir_path: Path, workers: int, only_images: bool, recursive: bool, max_depth: int = 0, machine_progress: bool = False) -> int:
    all_files = get_all_files(dir_path=dir_path, recursive=recursive, max_depth=max_depth)
    if only_images:
        all_files = get_all_images(all_files=all_files)
    all_files = [str(fpath) for fpath in all_files]
    if machine_progress:
        completed = 0
        total = len(all_files)
        with Pool(processes=workers) as p:
            for result in p.imap(make_thumbnail, all_files):
                completed += 1
                print(f"PROGRESS {completed}/{total} FILE {all_files[completed-1]}")
                sys.stdout.flush()
    else:
        with Pool(processes=workers) as p:
            list(tqdm(p.imap(make_thumbnail, all_files), total=len(all_files)))
    return 0


# Keep in sync with Images.validImageExtensions in
# modules/common/Images.qml -- the picker only renders these, so thumbnailing
# anything else just burns CPU. The original hardcoded
# [".jpg", ".jpeg", ".png", ".gif"], which silently skipped the webp/bmp/tiff/
# svg/avif wallpapers the user actually has.
IMG_SUFFIXES = [".jpg", ".jpeg", ".png", ".webp", ".avif", ".bmp", ".tif", ".tiff", ".svg"]

def get_all_images(*, all_files: List[Path]) -> List[Path]:
    img_suffixes = IMG_SUFFIXES
    all_images = [fpath for fpath in all_files if fpath.suffix.lower() in img_suffixes]
    print("Found {} images".format(len(all_images)))
    return all_images


def get_all_files(*, dir_path: Path, recursive: bool, max_depth: int = 0) -> List[Path]:
    if not (dir_path.exists() and dir_path.is_dir()):
        raise ValueError("{} doesn't exist or isn't a valid directory!".format(dir_path.resolve()))
    if recursive:
        # rglob("*") with no bound walks the entire tree. The wallpapers preset
        # lives under ~/Pictures, but the picker can be pointed at ~ (325k files
        # on this machine), so cap the depth. max_depth <= 0 means unlimited,
        # preserving the upstream default for direct CLI use.
        if max_depth and max_depth > 0:
            all_files = [f for f in dir_path.glob("**/*") if len(f.relative_to(dir_path).parts) <= max_depth]
        else:
            all_files = dir_path.rglob("*")
    else:
        all_files = dir_path.glob("*")
    all_files = [fpath for fpath in all_files if fpath.is_file()]
    print("Found {} files in the directory: {}".format(len(all_files), dir_path.resolve()))
    return all_files

@click.command()
@click.option(
    "-d",
    "--img_dirs",
    required=True,
    multiple=True,
    help="Directory to generate thumbnails for. Repeat the flag for multiple directories. Each value is taken verbatim, so names containing spaces work.",
)
@click.option(
    "-s", "--size", default="normal", type=click.Choice(["normal", "large", "x-large", "xx-large"]), help="Thumbnail size: normal, large, x-large, xx-large"
)
@click.option("-w", "--workers", default=1, help="no of cpus to use for processing")
@click.option(
    "-i", "--only_images", is_flag=True, default=False, help="Whether to only look for images to be thumbnailed"
)
@click.option("-r", "--recursive", is_flag=True, default=False, help="Whether to recursively look for files")
@click.option("--max_depth", type=int, default=0, help="Max directory depth to descend when --recursive is set (0 = unlimited). Guards against walking enormous trees.")
@click.option("--machine_progress", is_flag=True, default=False, help="Print machine-readable progress lines instead of a progress bar")
def main(img_dirs: list, size: str, workers: str, only_images: bool, recursive: bool, max_depth: int, machine_progress: bool) -> None:
    # Do NOT re-split these. Upstream accepted a single space-separated string
    # and called .split() on it, which made it structurally impossible to
    # thumbnail a directory whose name contains a space -- and the picker's own
    # default tree has one: "Wallpapers/SAVED (NO OVERRIDES)". Each -d is now one
    # directory; repeat the flag for more.
    img_dirs = [Path(img_dir) for img_dir in img_dirs]
    global factory
    factory = GnomeDesktop.DesktopThumbnailFactory.new(thumbnail_size_map[size])
    failed = [
        img_dir
        for img_dir in img_dirs
        if thumbnail_folder(
            dir_path=img_dir,
            workers=workers,
            only_images=only_images,
            recursive=recursive,
            max_depth=max_depth,
            machine_progress=machine_progress,
        )
        != 0
    ]
    if failed:
        # Exit non-zero so the caller's `||` fallback actually runs. It is
        # invoked with the same arguments and skips fresh thumbnails, so it
        # only redoes what failed here.
        for img_dir in failed:
            logger.error("thumbnail generation failed for {}".format(img_dir))
        print("Thumbnail Generation FAILED for {} of {} directories!".format(len(failed), len(img_dirs)))
        sys.exit(1)
    print("Thumbnail Generation Completed!")


if __name__ == "__main__":
    main()
