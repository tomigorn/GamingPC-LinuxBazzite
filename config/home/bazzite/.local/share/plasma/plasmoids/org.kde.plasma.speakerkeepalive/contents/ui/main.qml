import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    readonly property string reader: "cat \"$XDG_RUNTIME_DIR/speaker-keepalive\" 2>/dev/null || echo stopped"
    property string state: ""

    readonly property var states: ({
        "tone": { icon: "audio-speakers-symbolic", text: i18n("Tone on: keeping the speakers awake") },
        "headset": { icon: "audio-headset-symbolic", text: i18n("Tone off: headset in use") },
        "unreadable": { icon: "dialog-warning", text: i18n("Tone off: base station not readable (hidraw access?)") },
        "error": { icon: "dialog-warning", text: i18n("Tone should play but the Arctis sink is missing") },
        "stopped": { icon: "dialog-warning", text: i18n("speaker-keepalive.service is not running") }
    })
    readonly property var current: states[state] || { icon: "audio-speakers-symbolic", text: i18n("Reading…") }

    Plasma5Support.DataSource {
        id: source
        engine: "executable"
        connectedSources: []
        onNewData: function (cmd, data) {
            disconnectSource(cmd);
            root.state = (data["stdout"] || "").trim();
        }
        function refresh() {
            disconnectSource(root.reader);
            connectSource(root.reader);
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: source.refresh()
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
