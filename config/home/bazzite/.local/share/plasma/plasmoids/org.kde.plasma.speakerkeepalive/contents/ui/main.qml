import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property string runtimeDir: "/run/user/1000"
    readonly property string prefix: "speaker-keepalive."
    property string state: ""

    readonly property var states: ({
        "tone": { icon: "audio-speakers-symbolic", text: i18n("Tone on: keeping the speakers awake") },
        "headset": { icon: "audio-headset-symbolic", text: i18n("Tone off: headset in use") },
        "unreadable": { icon: "dialog-warning", text: i18n("Tone off: base station not readable (hidraw access?)") },
        "error": { icon: "dialog-warning", text: i18n("Tone should play but the Arctis sink is missing") },
        "stopped": { icon: "dialog-warning", text: i18n("speaker-keepalive.service is not running") }
    })
    readonly property var current: states[state] || { icon: "audio-speakers-symbolic", text: i18n("Reading…") }

    FolderListModel {
        id: files
        folder: "file://" + root.runtimeDir
        nameFilters: Object.keys(root.states).map(function (s) { return root.prefix + s; })
        showDirs: false
        onStatusChanged: root.sync()
        onCountChanged: root.sync()
    }

    Connections {
        target: files
        function onRowsInserted() { root.sync(); }
        function onRowsRemoved() { root.sync(); }
        function onModelReset() { root.sync(); }
        function onDataChanged() { root.sync(); }
    }

    function sync() {
        if (files.status !== FolderListModel.Ready)
            return;
        root.state = files.count > 0
            ? String(files.get(0, "fileName")).substring(root.prefix.length)
            : "stopped";
    }

    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    Plasmoid.icon: current.icon
    toolTipMainText: i18n("Speaker Keep-alive")
    toolTipSubText: current.text
    preferredRepresentation: compactRepresentation

    compactRepresentation: Kirigami.Icon {
        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small
        source: root.current.icon
        active: mouse.containsMouse
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
        }
    }

    fullRepresentation: PlasmaComponents.Label {
        text: root.current.text
    }
}
