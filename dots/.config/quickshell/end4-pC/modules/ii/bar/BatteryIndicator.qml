import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool vertical: false
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

    // Mirrors stock end-4's Icons.getBatteryIcon() (level -> MaterialSymbol glyph)
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
        radius: root.vertical ? 9999 : 6
        showTip: !root.vertical
        valueBarWidth: root.vertical ? 20 : 30
        valueBarHeight: root.vertical ? 36 : 18
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
                    spacing: 0
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.topMargin: 2
                        Layout.leftMargin: -2
                        Layout.rightMargin: -2
                        fill: 1
                        text: "bolt"
                        iconSize: Appearance.font.pixelSize.smaller
                        visible: root.isCharging && root.percentage < 1
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.topMargin: 2
                        font: batteryProgress.font
                        text: batteryProgress.text
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