import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell

/**
 * Prompts for a file name, then copies the current wallpaper into
 * "~/Pictures/Wallpapers/SAVED (NO OVERRIDES)" via
 * scripts/colors/save_current_wallpaper.sh. Never overwrites existing files.
 */
WindowDialog {
    id: root
    backgroundHeight: 320

    readonly property string targetDir: "~/Pictures/Wallpapers/SAVED (NO OVERRIDES)"

    onShowChanged: {
        if (show) {
            const path = Config.options.background.wallpaperPath
            nameField.text = path ? path.split("/").pop() : ""
            nameField.selectAll()
            statusText.text = ""
            nameField.forceActiveFocus()
        }
    }

    Process {
        id: saveProc
        property string status: ""
        command: ["bash", Quickshell.shellPath("scripts/colors/save_current_wallpaper.sh"), nameField.text.trim()]
        stdout: SplitParser {
            onRead: data => {
                saveProc.status = data.trim();
            }
        }
        onExited: code => {
            if (code === 0) {
                statusText.text = saveProc.status
                successTimer.start()
            } else {
                statusText.text = saveProc.status || Translation.tr("error: could not save the wallpaper")
            }
        }
    }

    Timer {
        id: successTimer
        interval: 900
        onTriggered: root.dismiss()
    }

    WindowDialogTitle {
        text: Translation.tr("Save wallpaper")
    }
    WindowDialogSeparator {
        Layout.topMargin: -22
        Layout.leftMargin: 0
        Layout.rightMargin: 0
    }

    StyledText {
        Layout.fillWidth: true
        text: Translation.tr("Copies the current wallpaper to %1 — never overwritten, safe from the Random buttons.").arg(root.targetDir)
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colOnLayer1
        opacity: 0.7
        wrapMode: Text.Wrap
    }

    MaterialTextField {
        id: nameField
        Layout.fillWidth: true
        placeholderText: Translation.tr("File name (extension optional)")
        onAccepted: saveButton.clicked()
    }

    StyledText {
        id: statusText
        Layout.fillWidth: true
        visible: text !== ""
        text: ""
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colPrimary
        wrapMode: Text.Wrap
    }

    WindowDialogButtonRow {
        Layout.fillWidth: true

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            id: cancelButton
            buttonText: Translation.tr("Cancel")
            onClicked: root.dismiss()
        }

        DialogButton {
            id: saveButton
            buttonText: Translation.tr("Save")
            enabled: !saveProc.running
            onClicked: {
                if (saveProc.running) return
                saveProc.running = true
            }
        }
    }
}