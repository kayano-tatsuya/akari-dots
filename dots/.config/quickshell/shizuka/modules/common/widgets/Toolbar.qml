import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Material 3 expressive style toolbar.
 * https://m3.material.io/components/toolbars
 */
Item {
    id: root

    property bool enableShadow: true
    property real padding: 8
    property alias colBackground: background.color
    property alias spacing: toolbarLayout.spacing
    default property alias data: toolbarLayout.data
    implicitWidth: background.implicitWidth
    implicitHeight: background.implicitHeight
    property alias radius: background.radius

    // Lets whoever instantiates this toolbar publish one of its inner items back
    // out through Loader.item. QML does not expose ids declared inside a
    // sourceComponent as properties of Loader.item, so an outer component
    // cannot reach a nested id directly -- but it can reach a declared property
    // of this root type. WallpaperSelectorContent uses this to drive the search
    // field's focus from its outer Keys handler.
    property var searchField: null

    Loader {
        active: root.enableShadow
        anchors.fill: background
        sourceComponent: StyledRectangularShadow {
            target: background
            anchors.fill: undefined
        }
    }

    Rectangle {
        id: background
        anchors.fill: parent
        color: Appearance.m3colors.m3surfaceContainer
        implicitHeight: 56
        implicitWidth: toolbarLayout.implicitWidth + root.padding * 2
        radius: height / 2

        // Plain Items don't consume mouse events in QML, so clicks on the
        // toolbar's empty areas would fall through to content underneath
        // (e.g. wallpaper grid cells). Block them; interactive children
        // (buttons, text fields) sit above and still get their own events.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            onClicked: (mouse) => mouse.accepted = true
            onWheel: (wheel) => wheel.accepted = true
        }

        RowLayout {
            id: toolbarLayout
            spacing: 4
            anchors {
                fill: parent
                margins: root.padding
            }
        }
    }
}
