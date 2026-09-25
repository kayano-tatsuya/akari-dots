import QtQuick
import Quickshell

import qs.modules.common
import qs.modules.akari.background
import qs.modules.akari.bar
import qs.modules.akari.dock
import qs.modules.akari.equalizer
import qs.modules.akari.lock
import qs.modules.akari.mediaControls
import qs.modules.akari.notificationPopup
import qs.modules.akari.onScreenDisplay
import qs.modules.akari.onScreenKeyboard
import qs.modules.akari.overview
import qs.modules.akari.polkit
import qs.modules.akari.settings
import qs.modules.akari.regionSelector
import qs.modules.akari.screenCorners
import qs.modules.akari.screenTranslator
import qs.modules.akari.sessionScreen
import qs.modules.akari.sidebarLeft
import qs.modules.akari.sidebarRight
import qs.modules.akari.overlay
import qs.modules.akari.verticalBar
import qs.modules.akari.wallpaperSelector
import qs.modules.akari.desktopMenu
import qs.modules.akari.dropover
import qs.modules.akari.frame

Scope {
    PanelLoader { extraCondition: !Config.options.bar.vertical; component: Bar {} }
    PanelLoader { component: Background {} }
    PanelLoader { extraCondition: Config.options.dock.enable; component: Dock {} }
    PanelLoader { component: EqualizerPopup {} }
    PanelLoader { component: Lock {} }
    PanelLoader { component: MediaControls {} }
    PanelLoader { component: NotificationPopup {} }
    PanelLoader { component: OnScreenDisplay {} }
    PanelLoader { component: OnScreenKeyboard {} }
    PanelLoader { component: Overlay {} }
    PanelLoader { component: Overview {} }
    PanelLoader { component: Polkit {} }
    PanelLoader { component: RegionSelector {} }
    PanelLoader { component: ScreenCorners {} }
    PanelLoader { component: ScreenTranslator {} }
    PanelLoader { component: SessionScreen {} }
    PanelLoader { component: SidebarLeft {} }
    PanelLoader { component: SidebarRight {} }
    PanelLoader { extraCondition: Config.options.bar.vertical; component: VerticalBar {} }
    PanelLoader { component: WallpaperSelector {} }
    PanelLoader { component: Settings {} }
    PanelLoader { component: DesktopMenu {} }
    PanelLoader { component: DropShelfPanel {} }
    PanelLoader { component: NiriBackdrop {} }
    PanelLoader { component: ScreenFrame {} }
}
