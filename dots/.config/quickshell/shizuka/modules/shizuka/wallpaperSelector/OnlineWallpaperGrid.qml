import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

Item {
    id: root

    property string provider: "wallhaven"
    property string resolution: "1080p"
    property string colorGroup: ""
    property int columns: Config.options.wallpaperSelector.columns || 4
    property real previewCellAspectRatio: 4 / 3
    property var hoveredItem: null

    signal wallpaperSelected(string path)
    signal updateThumbnailsRequested()

    readonly property bool unsplashMissingKey:
        root.provider === "unsplash" &&
        (KeyringStorage.keyringData?.apiKeys?.unsplash ?? "").length === 0

    readonly property bool pexelsMissingKey:
        root.provider === "pexels" &&
        (KeyringStorage.keyringData?.apiKeys?.pexels ?? "").length === 0
        
    readonly property bool pixivMissingKey:
        root.provider === "pixiv" && OnlineWallpapers.pixivTokenMissing

    readonly property bool missingKey:
        root.unsplashMissingKey || root.pexelsMissingKey || root.pixivMissingKey

    // Three providers need a credential, so resolve the notice text here rather
    // than as nested ternaries at each of the three call sites.
    readonly property string missingKeyTitle:
        root.unsplashMissingKey ? Translation.tr("Unsplash API key not set")
        : root.pexelsMissingKey   ? Translation.tr("Pexels API key not set")
        :                           Translation.tr("Pixiv refresh token not set")

    readonly property string missingKeyHint:
        root.unsplashMissingKey ? Translation.tr("Open the launcher and run:\n/unsplash YOUR_API_KEY")
        : root.pexelsMissingKey   ? Translation.tr("Open the launcher and run:\n/pexels YOUR_API_KEY")
        :                           Translation.tr("Open the launcher and run:\n/pixiv YOUR_REFRESH_TOKEN")

    readonly property string missingKeyFooter:
        root.unsplashMissingKey ? Translation.tr("Get your free key at unsplash.com/developers")
        : root.pexelsMissingKey   ? Translation.tr("Get your free key at pexels.com/api")
        :                           Translation.tr("Or get one once with the bundled pixiv-auth.py helper")

    // Set by onFetchError. Without this the only record of a failed fetch was a
    // console.log, so a provider that returned nothing (bad token, parse bug,
    // rate limit) looked exactly like a search that genuinely had no hits.
    property string errorMessage: ""

    onProviderChanged:   { root.hoveredItem = null; _syncAndFetch() }
    onResolutionChanged: _syncAndFetch()
    onColorGroupChanged: { if (root.provider === "naive" || root.provider === "blapples") _syncAndFetch() }

    function _syncAndFetch() {
        if (root.missingKey) return
        root.errorMessage = ""
        OnlineWallpapers.provider   = root.provider
        OnlineWallpapers.resolution = root.resolution
        OnlineWallpapers.colorGroup = root.colorGroup
        OnlineWallpapers.fetch()
    }

    function moveSelection(delta) {
        grid.currentIndex = Math.max(0, Math.min(wallpaperModel.count - 1, grid.currentIndex + delta))
        grid.positionViewAtIndex(grid.currentIndex, GridView.Contain)
    }

    function downloadItem(item, apply) {
        if (!item) return
        const url = item.full
        const urlLower = url.toLowerCase().split("?")[0]
        const ext = urlLower.includes(".png") ? "png"
            : urlLower.includes(".webp") ? "webp"
            : urlLower.includes(".jpeg") ? "jpg"
            : "jpg"
        const fileName = `${item.provider}-${item.id}.${ext}`
        const picturesPath = Directories.pictures.toString().replace("file://", "")
        const fullPath = `${picturesPath}/Wallpapers/${fileName}`
        // pixiv's CDN answers 403 to any request without a Referer, so the full-size
        // download needs the same header the thumbnails are fetched with.
        const refererArg = item.provider === "pixiv"
            ? ` -H 'Referer: ${OnlineWallpapers.pixivReferer}'`
            : ""
        downloadProc.filePath = fullPath
        downloadProc.applyAfter = apply
        downloadProc.command = ["bash", "-c",
            `mkdir -p '${picturesPath}/Wallpapers' && curl -L --silent '${item.full}'${refererArg} -o '${fullPath}'`
        ]
        downloadProc.running = true
    }

    function activateCurrent() {
        const item = wallpaperModel.get(grid.currentIndex)
        root.downloadItem(item, true)
    }

    Component.onCompleted: _syncAndFetch()

    ListModel { id: wallpaperModel }

    Connections {
        target: OnlineWallpapers
        function onFetched() {
            if (!OnlineWallpapers.appending) {
                wallpaperModel.clear()
                root.hoveredItem = null
            }
            const startIndex = wallpaperModel.count
            for (const item of OnlineWallpapers.results.slice(startIndex)) {
                wallpaperModel.append(item)
            }
        }
        function onFetchError(message) {
            console.log("[OnlineWallpaperGrid] Error:", message)
            root.errorMessage = message
        }
    }

    Process {
        id: downloadProc
        property string filePath: ""
        property bool applyAfter: false

        stdout: SplitParser {
            onRead: data => console.log("[download]", data)
        }

        onExited: (exitCode) => {
            if (exitCode === 0) {
                if (applyAfter) root.wallpaperSelected(filePath)
                Wallpapers.setDirectory(Wallpapers.effectiveDirectory)
                Qt.callLater(() => root.updateThumbnailsRequested())
                Quickshell.execDetached(["notify-send",
                    applyAfter ? Translation.tr("Wallpaper applied") : Translation.tr("Download complete"),
                    filePath, "-a", "Shell"
                ])
            } else {
                Quickshell.execDetached(["notify-send",
                    Translation.tr("Download failed"), filePath, "-a", "Shell"
                ])
            }
        }
    }

    // Missing key
    Item {
        anchors.fill: parent
        visible: root.missingKey

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 16

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "key_off"
                iconSize: 48
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                text: root.missingKeyTitle
                font.pixelSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                text: root.missingKeyHint
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.normal
                font.family: Appearance.font.family.main
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                text: root.missingKeyFooter
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }

    // Loading
    StyledIndeterminateProgressBar {
        visible: OnlineWallpapers.loading
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            leftMargin: 4
            rightMargin: 4
        }
    }

    // A failed fetch is reported here rather than only in the empty state: once any
    // result has loaded the empty state is hidden, so a later failure (a timed-out
    // page, a rate limit) used to stall with no visible explanation at all.
    Rectangle {
        visible: root.errorMessage.length > 0 && !OnlineWallpapers.loading
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 4
        }
        implicitHeight: errText.implicitHeight + 16
        radius: Appearance.rounding.normal
        color: Appearance.colors.colErrorContainer
        z: 5

        StyledText {
            id: errText
            anchors.centerIn: parent
            width: parent.width - 24
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.errorMessage
            color: Appearance.colors.colOnErrorContainer
        }
    }

    // Grid online
    Item {
        id: gridContainer
        anchors.fill: parent
        visible: !root.missingKey

        GridView {
            id: grid
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            visible: wallpaperModel.count > 0

            property int currentIndex: 0

            cellWidth: width / root.columns
            cellHeight: cellWidth / root.previewCellAspectRatio
            interactive: true
            acceptedButtons: Qt.NoButton
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            model: wallpaperModel

            delegate: Item {
                id: delegateItem
                required property var model
                required property int index

                width: grid.cellWidth
                height: grid.cellHeight

                Image {
                    id: thumb
                    anchors.fill: parent
                    anchors.margins: Appearance.sizes.wallpaperSelectorItemMargins
                    source: delegateItem.model.thumb
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: thumb.width
                            height: thumb.height
                            radius: Appearance.rounding.normal
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.normal
                        color: delegateItem.index === grid.currentIndex
                            ? Qt.rgba(
                                Appearance.colors.colPrimary.r,
                                Appearance.colors.colPrimary.g,
                                Appearance.colors.colPrimary.b, 0.15)
                            : "transparent"
                        border.width: delegateItem.index === grid.currentIndex ? 2 : 0
                        border.color: Appearance.colors.colPrimary
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer2
                        visible: thumb.status !== Image.Ready
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "image"
                            iconSize: 32
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onEntered: {
                        grid.currentIndex = delegateItem.index
                        root.hoveredItem = delegateItem.model
                        root.forceActiveFocus()
                    }
                    onExited: {
                        if (root.hoveredItem === delegateItem.model)
                            root.hoveredItem = null
                    }
                    onClicked: event => {
                        root.downloadItem(delegateItem.model, event.button === Qt.LeftButton)
                    }
                }

                RowLayout {
                    id: hoverActions
                    anchors {
                        bottom: thumb.bottom
                        right: thumb.right
                        margins: 6
                    }
                    z: 10
                    spacing: 4
                    Behavior on opacity { NumberAnimation { duration: 100 } }

                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: "transparent"

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "download"
                            iconSize: 15
                            color: Appearance.colors.colOnLayer0
                        }

                        MouseArea {
                            id: downloadMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.downloadItem(delegateItem.model, false)

                            StyledToolTip {
                                visible: downloadMouseArea.containsMouse
                                text: Translation.tr("Download")
                            }
                        }
                    }

                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: "transparent"

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "wallpaper"
                            iconSize: 15
                            color: Appearance.colors.colOnLayer0
                        }

                        MouseArea {
                            id: applyMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.downloadItem(delegateItem.model, true)

                            StyledToolTip {
                                visible: applyMouseArea.containsMouse
                                text: Translation.tr("Download and Set as Wallpaper")
                            }
                        }
                    }
                }
            }

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: grid.width
                    height: grid.height
                    radius: Appearance.rounding.screenRounding + 5
                }
            }
            onContentYChanged: {
                if (!OnlineWallpapers.loading
                    && contentY + height >= contentHeight - cellHeight * 1.5) {
                    OnlineWallpapers.nextPage()
                }
            }
        }

        // Empty state
        ColumnLayout {
            anchors.centerIn: parent
            visible: wallpaperModel.count === 0 && !OnlineWallpapers.loading
            spacing: 12

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "cloud_off"
                iconSize: 48
                color: Appearance.colors.colSubtext
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                text: root.errorMessage.length > 0
                    ? root.errorMessage
                    : Translation.tr("No results — try fetching again")
                color: Appearance.colors.colSubtext
            }

            RippleButton {
                Layout.alignment: Qt.AlignHCenter
                implicitHeight: 36
                buttonRadius: height / 2
                colBackground: Appearance.colors.colSecondaryContainer
                onClicked: { root.errorMessage = ""; OnlineWallpapers.fetch() }
                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        text: "refresh"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        text: Translation.tr("Retry")
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }
        }
    }
}
