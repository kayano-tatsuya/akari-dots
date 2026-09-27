pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string provider:   "wallhaven"  // "wallhaven" | "unsplash" | "pexels" | "blapples" | "naive" | "pixiv"
    property string resolution: "1080p"      // "1080p" | "2K" | "4K"
    property string query:      ""           // empty keyword = random
    property string colorGroup: ""           // naive: "" = all | "red"|"orange"|"yellow"|"green"|"blue"|"purple"
    property string category:   "general"    // wallhaven: "general"|"anime"|"people" / unsplash: "nature"|"city"|...
    property string purity:     "sfw"        // wallhaven: "sfw"|"sketchy"|"nsfw"
    property bool   loading:    false
    property bool   appending:  false 
    property int    page:       1
    property string seed:       ""          
    property var    results:    []           // list [ {thumb, full, id, provider} ]
    property int totalPages: 0

    property var _naiveFullResults: []
    property var _blapplesFullResults: []
    property var _pixivPending: []
    property int localPageSize: 24

    signal fetched()
    signal fetchError(string message)

    // ─── APIs ───
    readonly property string unsplashClientId: KeyringStorage.keyringData?.apiKeys?.unsplash  ?? ""
    readonly property string wallhavenApiKey:  KeyringStorage.keyringData?.apiKeys?.wallhaven ?? ""
    readonly property string pexelsApiKey: KeyringStorage.keyringData?.apiKeys?.pexels ?? ""

    // ─── Pixiv ───
    // The credential and the filter config are read from ~/.config/pixiv/, the same
    // place scripts/colors/random/pixiv-auth.py writes the token and
    // pixiv_nsfw.sh / pixiv_tag.sh write the flags. Deliberately not the OS
    // keyring: that would leave the shell and the random-pixiv button each holding
    // a separate copy of the same token, and they would drift.
    // trimFileProtocol because Directories.config carries a "file://" prefix, the
    // same reason shellConfig and every other path here strips it.
    readonly property string pixivDir:       `${FileUtils.trimFileProtocol(Directories.config)}/pixiv`
    readonly property string pixivTokenPath:  `${root.pixivDir}/refresh-token`
    readonly property string pixivConfigPath: `${root.pixivDir}/config`
    readonly property string pixivApiBase:    "https://app-api.pixiv.net"
    readonly property string pixivTokenUrl:   "https://oauth.secure.pixiv.net/auth/token"
    // pximg serves images only to requests carrying this Referer; without it every
    // image is a 403. Same value the random-pixiv script sends.
    readonly property string pixivReferer:    "https://www.pixiv.net/"
    readonly property string pixivUserAgent:  "PixivAndroidApp/5.0.234 (Android 11; Pixel 5)"
    // Sentinels separating the two files in one `cat`. Random-looking so they
    // cannot occur in a token or a shell config line.
    readonly property string _pixivTokMark: "---pixiv-token---"
    readonly property string _pixivCfgMark: "---pixiv-config---"

    // Refresh token, mirrored from disk. Re-read before every exchange so a token
    // minted by hand in a terminal is picked up without restarting the shell.
    property string _pixivRefreshToken: ""
    // Age gate, mirrored from PIXIV_ALLOW_NSFW. for_ios excludes adult work,
    // for_android includes it - it is a server-side filter, not a client-side one.
    property bool   _pixivAllowNsfw: false
    // Default query, mirrored from PIXIV_TAGS, so the tab searches what the
    // random button searches. Empty falls back to a wallpaper-ish tag.
    property string _pixivDefaultTags: ""
    // Raw contents of ~/.config/pixiv/config, kept for _pixivConfigValue().
    property string _pixivConfigText: ""
    // The read is async, so the grid must not report "no token" before it has run.
    property bool   _pixivReadDone: false

    readonly property bool pixivHasToken: _pixivRefreshToken.length > 0
    // What the grid should treat as "unconfigured": only once the read has
    // actually completed, otherwise the notice flashes on every open.
    readonly property bool pixivTokenMissing: _pixivReadDone && !root.pixivHasToken

    // Held in memory only and never written to the shell's own state: the access
    // token is short lived, and the refresh token stays in the pixiv config dir.
    property string _pixivAccessToken: ""
    // double, not int: QML's int is 32-bit and a ms unix timestamp is ~1.8e12, so
    // storing it in an int wraps negative and the validity check never passes.
    property double _pixivTokenExpiry: 0   // unix ms

    readonly property bool pixivTokenValid:
        _pixivAccessToken.length > 0 && Date.now() < _pixivTokenExpiry

    // Mirrors pixiv_tag.sh's get_value(): last assignment wins, surrounding quotes
    // stripped. Files sourced by the random script can set a key more than once.
    function _pixivConfigValue(key, fallback) {
        const text = root._pixivConfigText;
        if (!text) return fallback;
        const re = new RegExp("^" + key + "=(.*)$", "gm");
        let match, last = null;
        while ((match = re.exec(text)) !== null) last = match[1];
        if (last === null) return fallback;
        return last.trim().replace(/^["']/, "").replace(/["']$/, "");
    }

    // ─── Read the pixiv config dir ───
    // Quickshell 0.2.1 has FileView but no TextAdapter, so there is no way to bind
    // a plain text file declaratively. `cat` through a Process is the same shape
    // as every other network call in this file, and the two files come back in one
    // round trip separated by markers.
    //
    // onDone runs after _applyPixivRead() has updated state. It is a plain
    // property rather than an assigned onExited handler, because assigning that
    // would replace the handler that does the actual reading.
    property var _pixivReadContinuation: null

    // A search asked for while a fetch was already running is remembered and run as
    // soon as that fetch settles. The grid pages automatically on scroll, so the
    // Enter key races an in-flight page load often, and the loading guard used to drop
    // the search silently - indistinguishable from a search that found nothing.
    property bool _searchQueued: false

    function _readPixivFiles(onDone) {
        if (onDone !== undefined) root._pixivReadContinuation = onDone;
        const q = s => `'${StringUtils.shellSingleQuoteEscape(String(s))}'`;
        pixivReadProc.command = ["bash", "-c",
            `printf '%s' ${q(root._pixivTokMark)}`
            + `; cat ${q(root.pixivTokenPath)} 2>/dev/null`
            + `; printf '%s' ${q(root._pixivCfgMark)}`
            + `; cat ${q(root.pixivConfigPath)} 2>/dev/null`
        ];
        pixivReadProc.running = true;
    }

    // Called on readProc exit and again before each exchange, so a token minted
    // outside the shell is picked up without a restart.
    function _applyPixivRead() {
        const raw = pixivReadProc.buffer ?? "";
        const ti = raw.indexOf(root._pixivTokMark);
        const ci = raw.indexOf(root._pixivCfgMark);
        if (ti < 0 || ci < 0) {
            // Neither file readable. Leave state as-is; the fetch path reports the
            // missing token with a useful message.
            root._pixivReadDone = true;
            return;
        }
        root._pixivRefreshToken = raw.slice(ti + root._pixivTokMark.length, ci).trim();
        root._pixivConfigText = raw.slice(ci + root._pixivCfgMark.length);
        root._pixivAllowNsfw = _pixivConfigValue("PIXIV_ALLOW_NSFW", "false") === "true";
        root._pixivDefaultTags = _pixivConfigValue("PIXIV_TAGS", "");
        root._pixivReadDone = true;
    }

    Process {
        id: pixivReadProc
        // Process has no .buffer of its own in 0.2.1 - output is only captured by
        // attaching a SplitParser to stdout, as fetchProc/authProc/thumbProc all do.
        property string buffer: ""

        onRunningChanged: {
            if (running) buffer = "";
        }

        stdout: SplitParser {
            // Default splitMarker is "\n" and it is CONSUMED, not re-emitted, so a
            // multi-line file arrives as one run-on line and the ^KEY= regex in
            // _pixivConfigValue silently matches nothing. A marker that cannot occur
            // in a token or a shell config keeps the newlines intact.
            splitMarker: "\u0000"
            onRead: data => {
                pixivReadProc.buffer += data;
            }
        }

        onExited: {
            root._applyPixivRead();
            const continuation = root._pixivReadContinuation;
            root._pixivReadContinuation = null;
            if (continuation) continuation();
        }
    }

    Component.onCompleted: _readPixivFiles()

    // ─── Blapples ───
    readonly property string blapplesJsonUrl: "https://raw.githubusercontent.com/Blapples/wallpapers/main/wallpapers.json"
    readonly property string blapplesPagesBase: "https://raw.githubusercontent.com/Blapples/wallpapers/main/"
    readonly property string blapplesFullBase: "https://raw.githubusercontent.com/Blapples/wallpapers/main/"

    // ─── NA-ive ───
    readonly property string naiveJsonUrl: "https://raw.githubusercontent.com/na-ive/wallpapers/gh-pages/wallpapers.json"
    readonly property string naivePagesBase: "https://raw.githubusercontent.com/na-ive/wallpapers/gh-pages/"
    readonly property string naiveFullBase: "https://raw.githubusercontent.com/na-ive/wallpapers/main/"

    // ─── Resolution ───
    readonly property var resolutionMap: ({
        "wallhaven": {
            "1080p": "1920x1080",
            "2K":    "2560x1440",
            "4K":    "3840x2160",
        },
        "unsplash": {
            "1080p": "&w=1920&h=1080&fit=crop",
            "2K":    "&w=2560&h=1440&fit=crop",
            "4K":    "&w=3840&h=2160&fit=crop",
        },
        "pexels": {
            "1080p": "&w=1920&h=1080&fit=crop",
            "2K":    "&w=2560&h=1440&fit=crop",
            "4K":    "&w=3840&h=2160&fit=crop",
        }
    })

    // ─── Purity wallhaven ───
    readonly property var purityMap: ({
        "sfw":     "100",
        "sketchy": "110",
        "nsfw":    "111",
    })

    // Every provider ends a load by emitting fetched(); routing all of them through
    // here keeps the queue drain in one place instead of per-provider.
    function _finishFetch() {
        root.fetched();
        _drainQueuedSearch();
    }

    // Called on success (once the results are committed) and on the failure exits.
    // It must not run while a thumbnail batch is still in flight, or the queued
    // search would clear the results the batch is about to commit.
    function _drainQueuedSearch() {
        if (root._searchQueued && !root.loading) {
            root._searchQueued = false;
            root.fetch();
        }
    }

    function fetch() {
        if (root.loading) {
            root._searchQueued = true;
            return;
        }
        root.page = 1;
        root.seed = "";
        root.appending = false;
        root.results = [];
        _doFetch();
    }

    function nextPage() {
        if (root.loading) return;

        // Pixiv rate-limits per account and automated paging risks the account, so
        // stop at the configured ceiling instead of scrolling forever.
        if (root.provider === "pixiv" && root.page >= Config.options.wallpaperSelector.pixivMaxPages) {
            root.fetchError(Translation.tr("Pixiv: reached the page limit (%1). Raise sidebar.wallpaperSelector.pixivMaxPages to go further.").arg(Config.options.wallpaperSelector.pixivMaxPages));
            return;
        }

        if (root.provider === "naive" || root.provider === "blapples") {
            const full = root.provider === "naive" ? root._naiveFullResults : root._blapplesFullResults;
            if (root.page * root.localPageSize >= full.length) return;
            root.page += 1;
            root.appending = true;
            root.results = full.slice(0, root.page * root.localPageSize);
            root._finishFetch();
            return;
        }

        if (root.provider !== "unsplash" && root.totalPages > 0 && root.page >= root.totalPages) return;  // NUEVO: no pedir de más
        root.appending = true;   
        root.page += 1;
        _doFetch();
    }

    function prevPage() {
        if (root.loading || root.page <= 1) return;

        if (root.provider === "naive" || root.provider === "blapples") {
            const full = root.provider === "naive" ? root._naiveFullResults : root._blapplesFullResults;
            root.page -= 1;
            root.appending = false;
            root.results = full.slice(0, root.page * root.localPageSize);
            return;
        }

        root.page -= 1;
        _doFetch();
    }

    function _doFetch() {
        root.loading = true;
        if (root.provider === "wallhaven") {
            _fetchWallhaven();
        } else if (root.provider === "unsplash") {
            _fetchUnsplash();
        } else if (root.provider === "pexels") {
            _fetchPexels();
        } else if (root.provider === "blapples") {
            _fetchBlapples();
        } else if (root.provider === "naive") {
            _fetchNaive();
        } else if (root.provider === "pixiv") {
            _fetchPixiv();
        }
    }

    function goToPage(n) {
        root.page = n;

        if (root.provider === "naive" || root.provider === "blapples") {
            const full = root.provider === "naive" ? root._naiveFullResults : root._blapplesFullResults;
            root.appending = false;
            root.results = full.slice(0, root.page * root.localPageSize);
            return;
        }

        _doFetch();
    }

    function _fetchWallhaven() {
        const res      = root.resolutionMap["wallhaven"][root.resolution] ?? "1920x1080";
        const purity   = root.purityMap[root.purity] ?? "100";
        const apikey   = root.wallhavenApiKey.length > 0 ? `&apikey=${root.wallhavenApiKey}` : "";
        const q        = root.query.length > 0 ? `&q=${encodeURIComponent(root.query)}` : ""; 
        const seedParam = root.seed.length > 0 ? `&seed=${root.seed}` : "";

        const url = `https://wallhaven.cc/api/v1/search?sorting=random&purity=${purity}&categories=100&ratios=16x9&atleast=${res}&page=${root.page}${seedParam}${q}${apikey}`;

        fetchProc.provider = "wallhaven";
        fetchProc.command = ["curl", "-s", url];
        fetchProc.running = true;
    }

    function _fetchUnsplash() {
        const orientation = "landscape";
        const count       = 24;
        const q           = root.query.length > 0 ? `&query=${encodeURIComponent(root.query)}` : `&query=${encodeURIComponent(root.category)}`;  
        const clientId    = root.unsplashClientId;

        const url = `https://api.unsplash.com/photos/random?orientation=${orientation}&count=${count}${q}&client_id=${clientId}`;

        fetchProc.provider = "unsplash";
        fetchProc.command = ["curl", "-s", url];
        fetchProc.running = true;
    }

    function _fetchPexels() {
        const q = root.query.length > 0 ? root.query : "wallpaper landscape";
        const url = `https://api.pexels.com/v1/search?query=${encodeURIComponent(q)}&per_page=24&page=${root.page}`;
        fetchProc.provider = "pexels";
        fetchProc.command  = ["curl", "-s", "-H", `Authorization: ${root.pexelsApiKey}`, url];
        fetchProc.running  = true;
    }

    function _fetchBlapples() {
        fetchProc.provider = "blapples";
        fetchProc.command = ["curl", "-sL", root.blapplesJsonUrl];
        fetchProc.running = true;
    }

    function _fetchNaive() {
        fetchProc.provider = "naive";
        fetchProc.command = ["curl", "-sL", root.naiveJsonUrl];
        fetchProc.running = true;
    }

    // ─── Pixiv ───
    // Two round trips: swap the stored refresh token for a short-lived access
    // token, then search with that. The access token lives about an hour, so it is
    // cached in memory only and swapped again on demand.
    function _fetchPixiv() {
        // Re-read from disk first, so a token minted or rotated outside the shell
        // since the last fetch is picked up. The real work waits for the read.
        _readPixivFiles(() => _fetchPixivWithToken());
    }

    function _fetchPixivWithToken() {
        if (!root.pixivHasToken) {
            root.loading = false;
            root.fetchError(Translation.tr("No Pixiv refresh token found.\nGet one once with:\npython3 ~/.config/quickshell/akari/scripts/colors/random/pixiv-auth.py get-url"));
            return;
        }
        if (root.pixivTokenValid) {
            _doPixivSearch();
            return;
        }
        _exchangePixivToken(() => _doPixivSearch());
    }

    function _exchangePixivToken(onSuccess) {
        const clientId     = Config.options.wallpaperSelector.pixivClientId ?? "";
        const clientSecret = Config.options.wallpaperSelector.pixivClientSecret ?? "";
        authProc.onSuccess = onSuccess;
        authProc.command = ["curl", "-s", "--connect-timeout", "10", "--max-time", "30",
            "-X", "POST", root.pixivTokenUrl,
            "-H", `User-Agent: ${root.pixivUserAgent}`,
            "-d", `client_id=${clientId}`,
            "-d", `client_secret=${clientSecret}`,
            "-d", `grant_type=refresh_token`,
            "-d", `include_policy=true`,
            "-d", `refresh_token=${root._pixivRefreshToken}`
        ];
        authProc.running = true;
    }

    function _doPixivSearch() {
        // for_ios excludes adult work, for_android includes it. This is the same
        // switch the random-pixiv button uses, read from PIXIV_ALLOW_NSFW.
        const filter = root._pixivAllowNsfw ? "for_android" : "for_ios";
        const word = root.query.trim().length > 0
            ? root.query.trim()
            : (root._pixivDefaultTags.length > 0 ? root._pixivDefaultTags : "wallpaper");
        // Pixiv pages by offset, not page number. root.page is kept as a page
        // counter and multiplied here, so the existing nextPage()/prevPage() logic
        // and the max-pages cap both keep working unchanged.
        const offset = (root.page - 1) * Config.options.wallpaperSelector.pixivPageSize;

        const url = `${root.pixivApiBase}/v1/search/illust`
            + `?word=${encodeURIComponent(word)}`
            + `&search_target=partial_match_for_tags`
            + `&sort=date_desc`
            + `&filter=${filter}`
            + `&offset=${offset}`;

        fetchProc.provider = "pixiv";
        fetchProc.command = ["curl", "-s", "--connect-timeout", "10", "--max-time", "30",
            "-H", `Authorization: Bearer ${root._pixivAccessToken}`,
            "-H", `User-Agent: ${root.pixivUserAgent}`,
            url
        ];
        fetchProc.running = true;
    }

    function _parseWallhaven(jsonStr) {
        try {
            const data = JSON.parse(jsonStr);
            if (data.meta?.seed && root.seed.length === 0) {
                root.seed = data.meta.seed;
            }
            root.totalPages = data.meta?.last_page ?? 0
            const newItems = data.data.map(item => ({
                id:               item.id,
                thumb:            item.thumbs.large,
                full:             item.path,
                provider:         "wallhaven",
                title:            "",
                author:           "",
                authorUrl:        "",
                likes:            0,
                width:            item.dimension_x ?? 0,
                height:           item.dimension_y ?? 0,
                downloadLocation: "",
            }));
            root.results = root.appending ? root.results.concat(newItems) : newItems;   // CAMBIO
            root._finishFetch();
        } catch (e) {
            root.fetchError("Wallhaven parse error: " + e);
        }
    }

    function _parseUnsplash(jsonStr) {
        try {
            const data = JSON.parse(jsonStr);
            const resSuffix = root.resolutionMap["unsplash"][root.resolution] ?? "&w=1920&h=1080&fit=crop";

            const newItems = data.map(item => ({
                id:               item.id,
                thumb:            item.urls.small,
                full: item.urls.raw + (root.resolution === "4K" ? "&w=3840&h=2160&fit=crop&fm=jpg&q=85"
                    : root.resolution === "2K" ? "&w=2560&h=1440&fit=crop&fm=jpg&q=85"
                    : "&w=1920&h=1080&fit=crop&fm=jpg&q=85"),
                provider:         "unsplash",
                title:            item.alt_description ?? item.description ?? "",
                author:           item.user?.name ?? "",
                authorUrl:        item.user?.links?.html ?? "",
                likes:            item.likes ?? 0,
                width:            item.width ?? 0,
                height:           item.height ?? 0,
                downloadLocation: item.links?.download_location ?? "",
            }));

            root.results = root.appending ? root.results.concat(newItems) : newItems;
            root._finishFetch();
        } catch (e) {
            root.fetchError("Unsplash parse error: " + e);
        }
    }

    function _parsePexels(jsonStr) {
        try {
            const data = JSON.parse(jsonStr);
            const resSuffix = root.resolutionMap["pexels"][root.resolution] ?? "&w=1920&h=1080&fit=crop";

            root.totalPages = Math.ceil((data.total_results ?? 0) / 24);
            const newItems = data.photos.map(item => ({
                id:               String(item.id),
                thumb:            item.src.large,
                full: root.resolution === "4K" ? item.src.original + "?auto=compress&cs=tinysrgb&w=3840&h=2160&fit=crop"
                    : root.resolution === "2K" ? item.src.original + "?auto=compress&cs=tinysrgb&w=2560&h=1440&fit=crop"
                    :                            item.src.original + "?auto=compress&cs=tinysrgb&w=1920&h=1080&fit=crop",
                provider:         "pexels",
                title:            item.alt ?? "",
                author:           item.photographer ?? "",
                authorUrl:        item.photographer_url ?? "",
                likes:            0,
                width:            item.width ?? 0,
                height:           item.height ?? 0,
                avgColor:         item.avg_color ?? "",
                downloadLocation: "",
            }));

            root.results = root.appending ? root.results.concat(newItems) : newItems;
            root._finishFetch();
        } catch (e) {
            root.fetchError("Pexels parse error: " + e);
        }
    }

    function _parseBlapples(jsonStr) {
        try {
            const data = JSON.parse(jsonStr);
            if (!Array.isArray(data)) throw new Error("Unexpected wallpapers.json response");

            const q = root.query.trim().toLowerCase();
            const cg = root.colorGroup.trim().toLowerCase();
            const newItems = data
                .filter(item => item && item.filename)
                .filter(item => q.length === 0 || String(item.filename).toLowerCase().includes(q))
                .filter(item => cg.length === 0 || ((item.color_groups ?? []).map(g => String(g).toLowerCase()).includes(cg)))
                .map(item => {
                    const filename = String(item.filename);
                    const baseName = filename.replace(/\.[^.]+$/, "");
                    const dims = String(item.resolution ?? "").split("x");
                    const w = parseInt(dims[0], 10) || 0;
                    const h = parseInt(dims[1], 10) || 0;
                    return {
                        id:               baseName,
                        thumb:            root.blapplesPagesBase + String(item.thumbnail ?? item.preview ?? filename).split("/").map(encodeURIComponent).join("/"),
                        full:             root.blapplesFullBase + filename.split("/").map(encodeURIComponent).join("/"),
                        provider:         "blapples",
                        title:            baseName.replace(/[-_]+/g, " ").replace(/\b\w/g, c => c.toUpperCase()),
                        author:           "",
                        authorUrl:        "",
                        likes:            0,
                        width:            w,
                        height:           h,
                        avgColor:         item.color ?? "",
                        colorGroups:      (item.color_groups ?? []).map(g => String(g).toLowerCase()),
                        downloadLocation: "",
                    };
                });

            root._blapplesFullResults = newItems;
            root.totalPages = Math.max(1, Math.ceil(newItems.length / root.localPageSize));
            root.results = newItems.slice(0, root.localPageSize);
            root._finishFetch();
        } catch (e) {
            root.fetchError("Blapples parse error: " + e);
        }
    }

    function _parseNaive(jsonStr) {
        try {
            const data = JSON.parse(jsonStr);
            if (!Array.isArray(data)) throw new Error("Unexpected wallpapers.json response");

            const q = root.query.trim().toLowerCase();
            const cg = root.colorGroup.trim().toLowerCase();
            const newItems = data
                .filter(item => item && item.filename)
                .filter(item => q.length === 0 || String(item.filename).toLowerCase().includes(q))
                .filter(item => cg.length === 0 || ((item.color_groups ?? []).map(g => String(g).toLowerCase()).includes(cg)))
                .map(item => {
                    const filename = String(item.filename);
                    const baseName = filename.replace(/\.[^.]+$/, "");
                    const dims = String(item.resolution ?? "").split("x");
                    const w = parseInt(dims[0], 10) || 0;
                    const h = parseInt(dims[1], 10) || 0;
                    return {
                        id:               baseName,
                        thumb:            root.naivePagesBase + String(item.thumbnail ?? item.preview ?? filename),
                        full:             root.naiveFullBase + encodeURIComponent(filename),
                        provider:         "naive",
                        title:            baseName.replace(/[-_]+/g, " ").replace(/\b\w/g, c => c.toUpperCase()),
                        author:           "",
                        authorUrl:        "",
                        likes:            0,
                        width:            w,
                        height:           h,
                        avgColor:         item.color ?? "",
                        colorGroups:      item.color_groups ?? [],
                        downloadLocation: "",
                    };
                });

            root._naiveFullResults = newItems;
            root.totalPages = Math.max(1, Math.ceil(newItems.length / root.localPageSize));
            root.results = newItems.slice(0, root.localPageSize);
            root._finishFetch();
        } catch (e) {
            root.fetchError("NA-ive parse error: " + e);
        }
    }

    function _parsePixiv(jsonStr) {
        try {
            const data = JSON.parse(jsonStr);
            if (data.error) {
                const msg = data.errors?.system?.message ?? data.error?.message ?? "unknown error";
                root.fetchError("Pixiv: " + msg);
                return;
            }

            const all = (data.illusts ?? []).filter(item => item && item.image_urls);

            const clean = root._pixivAllowNsfw
                ? all
                // Belt and braces: filter= already excludes adult work server-side,
                // but x_restrict/sanity_level are re-checked here rather than
                // trusted, since this is the only age guard the tab has.
                // sanity_level 6 is R-18G, which x_restrict alone does not catch.
                : all.filter(item => (item.x_restrict ?? 0) === 0 && (item.sanity_level ?? 0) !== 6);

            // Wallpapers are landscape and most pixiv art is not, so prefer landscape
            // results - but fall back to the whole page rather than risk an empty
            // grid when a search has no landscape hits.
            const landscape = clean.filter(item => (item.width ?? 0) >= (item.height ?? 0) * 1.2);
            const source = landscape.length >= 8 ? landscape : clean;

            // The full-size URL is not in image_urls: a search result's image_urls
            // only carries square_medium/medium/large, and the original lives under
            // meta_single_page (or meta_pages[] for multi-page works, which is common
            // - page_count reaches the hundreds). Same fallback chain the random
            // script uses via jq.
            const originalUrl = item => {
                const single = item.meta_single_page?.original_image_url;
                if (single) return single;
                const firstPage = item.meta_pages?.[0];
                const fromPages = firstPage?.image_urls?.original ?? firstPage?.image_urls?.large;
                if (fromPages) return fromPages;
                return item.image_urls?.large ?? "";
            };

            // `thumb` points straight at the cache file this page's thumbnails are
            // about to be written to. The remote URL travels in `thumbUrl` only so
            // _fetchPixivThumbs knows what to pull.
            root._pixivPending = source.map(item => ({
                id:               String(item.id),
                thumb:            `${Directories.pixivPreviews}/${item.id}.jpg`,
                thumbUrl:         item.image_urls?.large ?? item.image_urls?.medium ?? "",
                full:             originalUrl(item),
                provider:         "pixiv",
                title:            item.title ?? "",
                author:           item.user?.name ?? "",
                authorUrl:        item.user?.id ? `https://www.pixiv.net/users/${item.user.id}` : "",
                likes:            item.total_bookmarks ?? 0,
                width:            item.width ?? 0,
                height:           item.height ?? 0,
                avgColor:         item.avg_color ?? "",
                // Carried so the grid can flag adult work the same way the random
                // script routes it, instead of guessing from the title.
                xRestrict:        item.x_restrict ?? 0,
                sanityLevel:      item.sanity_level ?? 0,
                downloadLocation: "",
            }));
            root.totalPages = Math.max(1, Config.options.wallpaperSelector.pixivMaxPages);

            _fetchPixivThumbs();
        } catch (e) {
            root.loading = false;
            root.fetchError("Pixiv parse error: " + e);
        }
    }

    // pximg serves images only to requests carrying a Referer, and quickshell's
    // Image cannot send one, so thumbnails are pulled to disk in a single batch and
    // the grid reads them as ordinary local files. One process per page rather than
    // one per delegate, which also keeps a recycled GridView from re-triggering
    // downloads it already has.
    function _fetchPixivThumbs() {
        const dir = Directories.pixivPreviews;
        const pending = root._pixivPending;
        // curl's own default User-Agent is rejected by several image CDNs, so send
        // the shell's configured one the same way the booru previews do.
        const ua = StringUtils.shellSingleQuoteEscape(
            Config.options?.networking?.userAgent ?? "Mozilla/5.0");

        const fetches = pending
            .filter(item => (item.thumbUrl ?? "").length > 0)
            .map(item =>
                // Download to .part and rename only on success. curl creates its
                // -o target before the transfer starts, and without --fail it treats
                // a 404 as success and writes the error page - either way a zero/short
                // .jpg would be left that the [ -f ] cache check treats as good
                // forever. --fail plus the rm keeps the cache self-healing: a failed
                // thumbnail is simply re-fetched next time.
                `[ -f '${dir}/${item.id}.jpg' ] || { ` +
                `curl -sSL --fail --connect-timeout 10 --max-time 45 ` +
                `-H 'Referer: ${root.pixivReferer}' -H 'User-Agent: ${ua}' ` +
                `'${item.thumbUrl}' -o '${dir}/${item.id}.jpg.part' ` +
                `&& mv -f '${dir}/${item.id}.jpg.part' '${dir}/${item.id}.jpg' ` +
                `|| rm -f '${dir}/${item.id}.jpg.part'; } &`
            );

        if (fetches.length === 0) {
            _commitPixivResults();
            return;
        }

        thumbProc.command = ["bash", "-c", `mkdir -p '${dir}'; { ${fetches.join(" ")} } ; wait`];
        thumbProc.running = true;
    }


    function _commitPixivResults() {
        root.results = root.appending ? root.results.concat(root._pixivPending) : root._pixivPending;
        root._pixivPending = [];
        root._finishFetch();
    }

    // ─── Pixiv token exchange ───
    // Kept separate from fetchProc because pixiv needs a token before it can
    // search, and fetchProc is busy for the duration of the search itself.
    Process {
        id: authProc
        property var onSuccess: null
        property string buffer: ""

        onRunningChanged: {
            if (running) buffer = "";
        }

        stdout: SplitParser {
            onRead: data => {
                authProc.buffer += data;
            }
        }

        onExited: (exitCode) => {
            if (exitCode !== 0) {
                root.loading = false;
                root.fetchError(Translation.tr("Pixiv: token request failed (curl exited with %1)").arg(exitCode));
                _drainQueuedSearch();
                return;
            }
            try {
                const auth = JSON.parse(authProc.buffer);
                if (!auth.access_token) {
                    root.loading = false;
                    root.fetchError("Pixiv: " + (auth.errors?.system?.message ?? Translation.tr("token exchange returned no access_token")));
                    return;
                }
                root._pixivAccessToken = auth.access_token;
                // Expire a minute early so a request never leaves with a token that
                // lapses in flight.
                root._pixivTokenExpiry = Date.now() + Math.max(0, (auth.expires_in ?? 3600) - 60) * 1000;

                // Pixiv returns a NEW refresh token on every exchange. Persist it, or
                // the copy on disk goes stale and eventually the random-pixiv script
                // starts failing on a token the shell has since replaced. Written
                // atomically at mode 600 via a temp file + rename, so a crash
                // mid-write cannot leave a truncated token behind.
                if (auth.refresh_token && auth.refresh_token !== root._pixivRefreshToken) {
                    root._pixivRefreshToken = auth.refresh_token;
                    _persistPixivRefreshToken(auth.refresh_token);
                }
            } catch (e) {
                root.loading = false;
                root.fetchError("Pixiv: token parse error: " + e);
                return;
            }
            if (authProc.onSuccess) authProc.onSuccess();
        }
    }

    function _persistPixivRefreshToken(token) {
        const q = s => `'${StringUtils.shellSingleQuoteEscape(String(s))}'`;
        saveProc.command = ["bash", "-c",
            `mkdir -p ${q(root.pixivDir)}`
            + ` && printf '%s\\n' ${q(token)} > ${q(root.pixivTokenPath + ".tmp")}`
            + ` && chmod 600 ${q(root.pixivTokenPath + ".tmp")}`
            + ` && mv -f ${q(root.pixivTokenPath + ".tmp")} ${q(root.pixivTokenPath)}`
        ];
        saveProc.running = true;
    }

    // ─── Persist rotated refresh token ───
    Process {
        id: saveProc
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                // Not fatal: the token in memory still works for this session, and
                // the old copy on disk is only a problem if Pixiv ever invalidates
                // it. Worth a log line, not worth failing the fetch over.
                console.warn("[OnlineWallpapers] could not persist rotated pixiv refresh token (curl exited with", exitCode + ")");
            }
        }
    }

    // ─── Pixiv thumbnail batch ───
    Process {
        id: thumbProc

        onExited: (exitCode) => {
            // A partial page should still render: whatever landed on disk is shown
            // and the grid's placeholder covers the rest, so a failed thumbnail is
            // not worth discarding a whole page of results over.
            if (exitCode !== 0) {
                console.log("[OnlineWallpapers] pixiv thumbnail batch exited with", exitCode);
            }
            root._commitPixivResults();
        }
    }

    // ─── Process ───
    Process {
        id: fetchProc
        property string provider: ""
        property string buffer:   ""

        onRunningChanged: {
            if (running) buffer = "";
        }

        stdout: SplitParser {
            onRead: data => {
                fetchProc.buffer += data;
            }
        }

        onExited: (exitCode) => {
            root.loading = false;
            if (exitCode !== 0) {
                root.fetchError("curl exited with code " + exitCode);
                _drainQueuedSearch();
                return;
            }
            if (fetchProc.provider === "wallhaven") {
                root._parseWallhaven(fetchProc.buffer);
            } else if (fetchProc.provider === "unsplash") {
                root._parseUnsplash(fetchProc.buffer);
            } else if (fetchProc.provider === "pexels") {
                root._parsePexels(fetchProc.buffer);
            } else if (fetchProc.provider === "blapples") {
                root._parseBlapples(fetchProc.buffer);
            } else if (fetchProc.provider === "naive") {
                root._parseNaive(fetchProc.buffer);
            } else if (fetchProc.provider === "pixiv") {
                root._parsePixiv(fetchProc.buffer);
            }
        }
    }
}