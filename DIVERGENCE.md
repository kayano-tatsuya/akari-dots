# Divergence from stock

Every intentional edit made to the inherited configuration, and why. This is
the map to consult before touching anything in `dots/`, because almost nothing
under `dots/` is stock any more.

Maintained by hand. Last updated 2026-09-27, covering all 33 commits on top
of `upstream/main`.

## The two baselines

This repo has three remotes, and "stock" means two different things depending
on which tree you are looking at. Getting this wrong is how you end up
"restoring" something that was a deliberate change.

| Remote | What it is | Role |
| --- | --- | --- |
| `upstream` | `end-4/dots-hyprland` @ `2f0c8bf4` | Stock. Baseline for Hyprland, installer, docs. |
| `pctrade` | `pctrade/end4-pC` | The shell we actually forked. Contains our commits. |
| `origin` | `kayano-tatsuya/akari-dots` | This repo. |

**Hyprland, installer and docs** are diffed against `upstream/main`. All 32
commits sit on top of it.

**The Quickshell shell is not end-4 stock at all.** end-4's own `ii` tree was
deleted outright (916 files, −74,185 lines, commit `e9ff3b75`) and replaced
with a snapshot of pctrade's `end4-pC` (`8efd7b37`, snapshot `0ff392bc`,
706 files, +100,742 lines). It was then renamed to `akari` (`769958dd`,
712 files, +191/−182 — mechanical path and identifier churn only).

So for anything under `dots/.config/quickshell/akari/`, the meaningful baseline
is **`0ff392bc`**, not `upstream/main`. Diffing the akari tree against
`upstream/main` shows +102,527 lines across 713 files, which is almost entirely
the vendored snapshot and the rename, not our work.

Current rename map, applied wholesale in `769958dd`:

```
dots/.config/quickshell/end4-pC/  ->  dots/.config/quickshell/akari/
  modules/ii/                     ->  modules/akari/
  modules/common/                 ->  modules/common/   (unchanged)
```

## 1. Wallpaper: random sources, saving, and Pixiv

The largest body of deliberate change. All of it lives in the wallpaper
settings page plus a family of standalone scripts it shells out to.

| File | Edit |
| --- | --- |
| `modules/akari/settings/pages/BackgroundConfig.qml` | Source of most of the below. Adds the **Random: Konachan** and **Random: Pixiv** buttons, the **Save wallpaper** button, the Pixiv **R-18** toggle, and the wallpaper-tag switch; reorders the page so Save sits above Konachan and the Pixiv toggles sit in a labelled section. |
| `modules/common/widgets/SaveWallpaperDialog.qml` | **New.** Name-prompt dialog for saving the current wallpaper. |
| `modules/akari/settings/Settings.qml`, `GlobalStates.qml` | Makes the save dialog open **modally over** the settings window instead of behind it, and stops the settings dialog from blocking. |
| `modules/akari/sidebarRight/SidebarRightContent.qml` | Surfaces Save wallpaper in the sidebar; fixes a stale quick-toggle edit tooltip. |
| `modules/akari/wallpaperSelector/WallpaperSelectorContent.qml` | **Homework folder** auto-creation and routing of R-18 Pixiv pulls into it, so adult content is never dropped into the general wallpaper pool. |

### Scripts the settings page invokes

| Script | Edit |
| --- | --- |
| `scripts/colors/random/pixiv-auth.py` | **New.** Mints and stores a Pixiv refresh token. Writes `~/.config/pixiv/refresh-token` at mode 600. Sole supported writer of that file. |
| `scripts/colors/random/random_pixiv_wall.sh` | **New.** Random Pixiv pull: auth, tag filters, NSFW gating, Homework routing. |
| `scripts/colors/random/pixiv_nsfw.sh`, `pixiv_tag.sh` | **New.** Toggles the R-18 flag and the wallpaper-tag flag, read by the script above. |
| `scripts/colors/random/random_konachan_wall.sh` | Refresh added to stop the random pick repeating stale previews. |
| `scripts/colors/save_current_wallpaper.sh` | **New.** Backs the Save wallpaper button. |
| `scripts/colors/switchwall.sh` | Thumbnail refresh on wallpaper switch. |

### `random_osu_wall.sh`, removed

Called `osu.ppy.sh/api/v2/seasonal-backgrounds`, part of the osu! v2 API that no
longer exists, so the script could only fail. Nothing invoked it: no QML and no
JS in the tree mentions `osu` or `seasonal`, and no keybind or settings entry
calls it by name.

Its `"Random • osu! seasonal"` strings were orphaned catalogue entries with no
caller, and were pruned from all 10 locales that had them (18 lines, deletions
only). They were removed line-by-line rather than by re-serialising the JSON:
`json.dump` reformats 9 of the 14 files, because they do not share a separator
style, and a bulk rewrite would have buried an 18-line deletion inside a
whole-tree reformat.

### Where the Pixiv app credentials live

The `for_android` client pair is hardcoded in `Config.qml` as the built-in
default, and `PIXIV_CLIENT_ID` / `PIXIV_CLIENT_SECRET` in
`~/.config/pixiv/config` override it. `pixiv_nsfw.sh` and `pixiv_tag.sh` already
described that file as the single source of truth for Pixiv settings; it now
actually is one, for the credentials too.

The default is kept deliberately. The QML side already held the raw config text
in memory from the existing refresh-token read, so the override is two extra
lookups against a string already loaded — no new I/O and no new async in a
token-exchange path that has already produced two subtle bugs. Without the
default, a missing or mistyped override would post an empty `client_id` and
surface as Pixiv's generic error with no hint at the cause. An override that is
present but *blank* counts as absent in all three readers, because it matches
the key regex and would otherwise defeat the fallback.

## 2. Wallpaper picker repairs

Defects inherited from `end4-pC` and fixed in place.

| File | Edit |
| --- | --- |
| `modules/akari/wallpaperSelector/LocalWallpaperGrid.qml`, `services/Wallpapers.qml` | Repairs **folder navigation** in the local grid. |
| `modules/akari/wallpaperSelector/LocalWallpaperGrid.qml`, `WallpaperSelectorContent.qml`, `services/Wallpapers.qml` | Generates previews for images in **subfolders**, not just the wallpaper root. |
| `modules/common/widgets/Toolbar.qml`, `WallpaperSelectorContent.qml` | Reaches the search field **through the toolbar Loader**, which the inherited code did not do, so the field could not be focused at all. |
| `WallpaperSelectorContent.qml` | Reveals the **search bar when you start typing** into it. |

`scripts/thumbnails/` — `thumbgen.py`, `check-thumbnails.py`,
`check-thumbnails-venv.sh`, `generate-thumbnails-magick.sh` — were reworked
alongside the subfolder preview fix.

## 3. Shell chrome and services

Seven live defects fixed in the bar, overview, vertical bar and services.

| File | Edit |
| --- | --- |
| `modules/akari/bar/BarContent.qml`, `modules/akari/verticalBar/VerticalBarContent.qml`, `modules/akari/overview/OverviewWindow.qml` | Layout and behaviour repairs inherited from `end4-pC`. |
| `modules/akari/bar/BatteryIndicator.qml`, `Resource.qml`, `SysTray.qml`, `modules/common/widgets/ClippedProgressBar.qml` | All three bar widgets read `bar.vertical` from the config instead of a hardcoded `false`: `VerticalBarContent` stamps `vertical = true` onto loaded widgets but `BarContent` does not, so the hardcoded default was the only thing orienting them in a horizontal bar. `BatteryIndicator` additionally drops the orientation-dependent shape — a horizontal bar used to fall back to `radius: 6` with the Android-battery nub showing, so the capsule is now used in both orientations (horizontal slot widened 30→44px) and the horizontal reading gained the same level glyph the vertical one already had. `ClippedProgressBar` shed the fork-only `showTip` tip machinery as dead code. |
| `services/Notifications.qml`, `services/Updates.qml` | Service-level repairs. |

## 4. Hyprland

| File | Edit |
| --- | --- |
| `hypr/custom/*.lua` (6 files) | **Now comments-only templates.** We shipped our own keybinds and input settings in here, which meant a fresh clone arrived with a personal floorp path and mouse config already set. Each file now documents its own syntax inline and loads as a no-op, except the deliberate "Edit user keybinds" helper in `keybinds.lua` so a fresh install has a way in. Installer handles this as `mode: skip-if-exists`; do not change it to `sync`, it would clobber the user's config. |
| `hypr/hyprland/keybinds.lua` | `SUPER + I` → `quickshell:settingsToggle`, "Shell: Toggle settings" (line 354). |
| `hypr/hyprland/variables.lua` | Config variables added alongside the binding. |
| `hypr/hyprland/execs.lua` | Starts the shell at boot with `qs -c $qsConfig`. Note `$qsConfig` is **not** defined anywhere in this repo — it resolves from the live config, so do not assume the profile name when editing. Also runs the `wl-paste` clipboard watchers. |
| `hypr/hyprlock/status.sh` | Repair. |

## 5. Installer (`sdata/`)

| File | Edit |
| --- | --- |
| `subcmd-install/3.files-exp.sh`, `lib/dist-determine.sh` | Correct `ID_LIKE` matching; export installer vars. |
| `lib/package-installers.sh` | Fixes `STY_RESET`. |
| `subcmd-install/3.files-exp.yaml` | Expands the Quickshell sync to the whole `dots/.config/quickshell` tree. |

The installer is strictly **one-way, repo → live**. It never reads from or
writes to the live config. This is load-bearing for the credential decision
below.

## 6. Docs and repo hygiene

| File | Edit |
| --- | --- |
| `AGENTS.md` | Working rules for this repo. Read before changing anything. |
| `.github/README.md` | Replaced the inherited README with an akari-dots one. |
| `hypr/custom/README.md` | Explains the comments-only template convention. |
| `.gitignore` | Adds `config.json`, the locally-owned akari config holding API keys. |

## 7. Pixiv as a wallpaper picker source

The newest addition, and the one with the most decisions attached to it. Seven
files, +596/−24.

Adds pixiv as a sixth source in the wallpaper picker (`CTRL+SHIFT+T`),
alongside local, wallhaven, blapples, naive, unsplash and pexels: searchable
grid, download, apply.

| File | Edit |
| --- | --- |
| `services/OnlineWallpapers.qml` | All pixiv logic: token exchange and reuse, search, paging, the `full` URL fallback chain, thumbnail caching, and the search queue. |
| `modules/akari/wallpaperSelector/OnlineWallpaperGrid.qml` | Pixiv in the provider combo; the `Referer` header on download; **errors now surface** in a banner instead of only in the empty state, which previously hid every failure after the first page. |
| `WallpaperSelectorContent.qml` | Registers pixiv as a provider, excludes it from the resolution toolbar. |
| `services/LauncherSearch.qml` | Adds `/pixiv YOUR_REFRESH_TOKEN`, alongside the existing `/unsplash`, `/wallhaven`, `/pexels`. |
| `modules/common/Config.qml` | Pixiv client constants, `pixivMaxPages`, `pixivPageSize`. |
| `modules/common/Directories.qml` | `pixivPreviews` cache directory. |
| `modules/common/utils/ImageDownloaderProcess.qml` | `downloadReferer` support. |

### Decisions worth not relitigating

**The refresh token lives in `~/.config/pixiv/refresh-token`, not the keyring.**
Deliberate. `KeyringStorage` is a single JSON blob (service `application`,
name `illogical-impulse`, label "akari Safe Storage") holding every provider
key at once. That suits the QML shell, which parses JSON natively, but it is
hostile to shell: `pixiv-auth.py` and `random_pixiv_wall.sh` would each need
`secret-tool lookup` plus JSON parsing to extract one field, and a keyring read
requires a live session bus. Verified on this machine — with no D-Bus,
`secret-tool` fails with `Cannot autolaunch D-Bus without X11 $DISPLAY`, so any
cron or systemd caller would break. A mode-600 file also fails legibly: the
picker names the missing path, whereas a *locked* keyring makes
`KeyringStorage` reset to `{}` and your keys look deleted.

It is safe from the repo because it lives outside the repo root and the
installer only maps `dots/.config/quickshell` → `~/.config/quickshell`. A
`.gitignore` rule could not protect it even if we wanted one, since git ignore
rules do not reach outside the tree. **Revisit only if `~/.config` ever becomes
a git tree.**

**Auto-paging is kept but capped** at `Config.pixivMaxPages` (10). Pixiv
rate-limits per personal account, so unbounded scrolling is not an option.

**A search issued while a page load is in flight is queued**, not dropped. The
`loading` guard used to discard it silently, which was indistinguishable from a
search that found nothing.

**NSFW follows `PIXIV_ALLOW_NSFW`** in `~/.config/pixiv/config`, so the picker
agrees with the Random: Pixiv R-18 switch instead of fighting it, with a
client-side re-filter as a second line.

**Downloads need `-H 'Referer: https://www.pixiv.net/'`.** Pixiv's CDN answers
403 without it. Thumbnails are cached under `~/.cache/quickshell/media/pixiv`
because quickshell's `Image` cannot send a Referer; cache entries are written
to `.part` and moved into place only on success so a 404 cannot poison them.

## Attribution

The Quickshell shell descends from `pctrade/end4-pC`, which descends from
end-4/pC, and is GPL-3.0. `end-4` and `pctrade` attribution is preserved
throughout and `LICENSE` is unmodified. See also `licenses/README.md`.
