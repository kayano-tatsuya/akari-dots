import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    // VerticalBarContent stamps vertical = true onto loaded widgets, but
    // BarContent never does, so this hardcoded default was the only thing
    // orienting the indicator in a horizontal bar. Read the config like
    // SystemIcons/Workspaces/Divisor/... do so both bar flavours agree.
    property bool vertical: Config.options.bar.vertical
    property bool borderless: Config.options.bar.borderless
    property bool isMaterial: Config.options.bar.cornerStyle === 3
    readonly property var chargeState: Battery.chargeState
    readonly property bool isCharging: Battery.isCharging
    readonly property bool isPluggedIn: Battery.isPluggedIn
    readonly property real percentage: Battery.percentage
    readonly property bool isLow: percentage <= Config.options.battery.low / 100
    readonly property string displayText: (root.vertical && root.percentage > 99) ? "" : batteryProgress.text

    implicitWidth:  vertical ? Appearance.sizes.verticalBarWidth : batteryProgress.valueBarWidth + 8
    implicitHeight: vertical ? batteryProgress.valueBarHeight + 8 : Appearance.sizes.barHeight

    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    // Mirrors upstream Icons.getBatteryIcon() (level -> MaterialSymbol glyph)
    function batteryLevelIcon(): string {
        const percentage = Math.round(batteryProgress.value * 100);
        if (percentage >= 93) return "battery_android_full";
        if (percentage >= 78) return "battery_android_6";
        if (percentage >= 64) return "battery_android_5";
        if (percentage >= 50) return "battery_android_4";
        if (percentage >= 35) return "battery_android_3";
        if (percentage >= 21) return "battery_android_2";
        if (percentage >= 7)  return "battery_android_1";
        return "battery_android_0";
    }

    ClippedProgressBar {
        id: batteryProgress
        anchors.centerIn: parent
        value: percentage
        vertical: root.vertical
        // Capsule in both orientations. In a horizontal bar this widget used
        // to fall back to a 6px radius with the Android-battery nub, because
        // the vertical branch (radius 9999, no tip) only kicked in when the
        // outer widget got its `vertical` set -- something BarContent never
        // did.
        radius: 9999
        valueBarWidth: root.vertical ? 20 : 44
        valueBarHeight: root.vertical ? 36 : 20
        highlightColor: (isLow && !isCharging) ? Appearance.m3colors.m3error : Appearance.colors.colOnSecondaryContainer
        Item {
            anchors.centerIn: parent
            width: batteryProgress.valueBarWidth
            height: batteryProgress.valueBarHeight
            // Horizontal
            Loader {
                id: rowLoader
                active: !root.vertical
                visible: active
                anchors.centerIn: parent
                sourceComponent: RowLayout {
                    spacing: 2
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        fill: 1
                        text: {
                            if (batteryProgress.value == 1) return "check";
                            if (root.isCharging) return "bolt";
                            return root.batteryLevelIcon();
                        }
                        iconSize: Appearance.font.pixelSize.normal
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        font: batteryProgress.font
                        text: batteryProgress.text
                        // a 3-digit "100" plus the level glyph crams against the
                        // capsule's ends; the vertical branch already hides it
                        visible: text.length <= 2
                    }
                }
            }
            // Vertical
            Loader {
                id: colLoader
                active: root.vertical
                visible: active
                anchors.centerIn: parent
                sourceComponent: Column {
                    anchors.centerIn: parent
                    spacing: -4
                    MaterialSymbol {
                        anchors.horizontalCenter: parent.horizontalCenter
                        fill: 1
                        text: {
                            if (batteryProgress.value == 1) return "check";
                            if (root.isCharging) return "bolt";
                            return root.batteryLevelIcon();
                        }
                        iconSize: Appearance.font.pixelSize.normal
                    }
                    StyledText {
                        visible: text.length <= 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        font: batteryProgress.font
                        text: batteryProgress.text
                    }
                }
            }
        }
    }

    BatteryPopup {
        id: batteryPopup
        hoverTarget: root
    }
}