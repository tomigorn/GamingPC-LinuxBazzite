import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    readonly property string collector: "/home/bazzite/.local/bin/peripheral-battery"

    property var devices: []
    property var collectErrors: []
    property string lastUpdate: ""
    property bool everLoaded: false

    /* Devices with a known level that are NOT on the charger decide the tray icon --
       they are the ones that can actually run out. Without this a spare battery sitting
       in the Arctis dock at 25 % would drag the icon down and flip it to "charging"
       while every device in use is still near full. If everything happens to be
       charging, fall back to the whole set so the icon still means something. */
    readonly property var iconDevices: {
        var levelled = [];
        var active = [];
        for (var i = 0; i < devices.length; ++i) {
            var d = devices[i];
            if (d.percent === null || d.percent === undefined)
                continue;
            levelled.push(d);
            if (!isCharging(d))
                active.push(d);
        }
        return active.length > 0 ? active : levelled;
    }

    // Lowest percentage among those; -1 when nothing reports a level.
    readonly property int lowestPercent: {
        var lo = -1;
        for (var i = 0; i < iconDevices.length; ++i) {
            var p = iconDevices[i].percent;
            if (lo < 0 || p < lo)
                lo = p;
        }
        return lo;
    }

    // Only show the charging icon when the device the icon represents is charging.
    readonly property bool iconCharging: {
        if (iconDevices.length === 0)
            return false;
        for (var i = 0; i < iconDevices.length; ++i)
            if (!isCharging(iconDevices[i]))
                return false;
        return true;
    }

    readonly property int lowThreshold: Plasmoid.configuration.lowThreshold

    // Devices that actually need charging: known level, at or below the threshold,
    // and not already on the charger.
    readonly property var lowDevices: {
        var out = [];
        for (var i = 0; i < devices.length; ++i) {
            var d = devices[i];
            if (isLow(d))
                out.push(d);
        }
        return out;
    }

    readonly property int lowCount: lowDevices.length

    function isCharging(dev) {
        return dev.status === "charging" || dev.status === "fully-charged"
            || dev.status === "pending-charge";
    }

    function isLow(dev) {
        return dev.percent !== null && dev.percent !== undefined
            && dev.percent <= lowThreshold && !isCharging(dev);
    }

    function kindIcon(kind) {
        switch (kind) {
        case "mouse":    return "input-mouse";
        case "keyboard": return "input-keyboard";
        case "headset":  return "audio-headset";
        default:         return "battery-full";
        }
    }

    // Breeze ships battery-000 .. battery-100 in 10% steps, plus -charging variants.
    function batteryIcon(percent, charging, symbolic) {
        if (percent === null || percent === undefined || percent < 0)
            return symbolic ? "battery-missing-symbolic" : "battery-missing";
        var step = Math.max(0, Math.min(100, Math.round(percent / 10) * 10));
        var name = "battery-" + ("00" + step).slice(-3);
        if (charging)
            name += "-charging";
        return symbolic ? name + "-symbolic" : name;
    }

    function percentText(dev) {
        return (dev.percent === null || dev.percent === undefined) ? "—" : dev.percent + " %";
    }

    Plasma5Support.DataSource {
        id: collectorSource
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            disconnectSource(source);

            var stdout = (data["stdout"] || "").trim();
            var stderr = (data["stderr"] || "").trim();

            if (stdout.length === 0) {
                root.devices = [];
                root.collectErrors = [stderr.length ? stderr
                                                   : "no output from " + root.collector];
            } else {
                try {
                    var parsed = JSON.parse(stdout);
                    root.devices = parsed.devices || [];
                    root.collectErrors = parsed.errors || [];
                } catch (e) {
                    root.devices = [];
                    root.collectErrors = ["could not parse collector output: " + e];
                }
            }

            root.everLoaded = true;
            root.lastUpdate = Qt.formatTime(new Date(), "hh:mm");
            root.updateLowWarnings();
        }

        function refresh() {
            disconnectSource(root.collector);
            connectSource(root.collector);
        }
    }

    // Separate source so notify-send output never reaches the JSON parser above.
    Plasma5Support.DataSource {
        id: shell
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            disconnectSource(source);
        }
        function exec(cmd) {
            disconnectSource(cmd);
            connectSource(cmd);
        }
    }

    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    /* Warn once per low episode. A device is remembered in notifiedDevices until it
       climbs back above lowThreshold + 5 (or goes on the charger), which re-arms it —
       the margin stops a device hovering right at the threshold from flapping. */
    function updateLowWarnings() {
        var notified = (Plasmoid.configuration.notifiedDevices || []).slice();
        var changed = false;
        var fresh = [];

        for (var i = 0; i < devices.length; ++i) {
            var dev = devices[i];
            if (dev.percent === null || dev.percent === undefined)
                continue;

            var idx = notified.indexOf(dev.name);
            if (isLow(dev)) {
                if (idx === -1) {
                    notified.push(dev.name);
                    fresh.push(dev);
                    changed = true;
                }
            } else if (idx !== -1 && (isCharging(dev) || dev.percent > lowThreshold + 5)) {
                notified.splice(idx, 1);
                changed = true;
            }
        }

        if (changed)
            Plasmoid.configuration.notifiedDevices = notified;
        if (fresh.length > 0)
            notifyLow(fresh);
    }

    function notifyLow(lowList) {
        var title, body;
        if (lowList.length === 1) {
            title = i18n("Battery low");
            body = i18n("%1 is at %2 %", lowList[0].name, lowList[0].percent);
        } else {
            title = i18n("Batteries low");
            var lines = [];
            for (var i = 0; i < lowList.length; ++i)
                lines.push(lowList[i].name + ": " + lowList[i].percent + " %");
            body = lines.join("\n");
        }

        shell.exec("notify-send -a " + shellQuote(i18n("Peripheral Battery"))
                   + " -i battery-caution -t 5000 -u normal "
                   + shellQuote(title) + " " + shellQuote(body));
    }

    /* At login the panel can start before the dongles and the headset base station have
       finished enumerating, which would leave the widget blank for a full poll interval.
       Poll quickly until something reports an actual level, then settle down. Capped so a
       genuinely idle setup (headset switched off) does not keep polling fast forever. */
    property bool everSawLevel: false
    property int pollCount: 0
    readonly property bool settled: everSawLevel || pollCount >= 5

    onLowestPercentChanged: if (lowestPercent >= 0) everSawLevel = true;

    Timer {
        interval: root.settled ? 2 * 60 * 1000 : 15 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.pollCount++;
            collectorSource.refresh();
        }
    }

    // Refresh when the popup opens so the numbers are never stale on screen.
    // Qualify with root: the bare name would bind to the deprecated injected signal
    // parameter, which Qt warns about and will eventually stop providing.
    onExpandedChanged: if (root.expanded) collectorSource.refresh()

    Plasmoid.status: PlasmaCore.Types.ActiveStatus

    toolTipMainText: i18n("Peripheral Batteries")
    toolTipSubText: {
        if (!everLoaded)
            return i18n("Reading…");
        if (devices.length === 0)
            return i18n("No supported devices found");
        var lines = [];
        for (var i = 0; i < devices.length; ++i)
            lines.push((isLow(devices[i]) ? "⚠ " : "") + devices[i].name + ": "
                       + (devices[i].stale ? "~" : "") + percentText(devices[i]));
        if (lowCount > 0)
            lines.push(i18np("%1 device needs charging", "%1 devices need charging", lowCount));
        return lines.join("\n");
    }

    compactRepresentation: MouseArea {
        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onClicked: function (mouse) {
            if (mouse.button === Qt.MiddleButton)
                collectorSource.refresh();
            else
                root.expanded = !root.expanded;
        }

        Kirigami.Icon {
            id: trayIcon
            anchors.fill: parent
            source: root.batteryIcon(root.lowestPercent, root.iconCharging, true)
            active: parent.containsMouse
        }

        // Count of devices needing a charge, as a badge over the icon's corner.
        Rectangle {
            id: badge
            visible: root.lowCount > 0
            z: 1

            readonly property int diameter: Math.max(Kirigami.Units.gridUnit * 0.6,
                                                     Math.round(Math.min(trayIcon.width,
                                                                         trayIcon.height) * 0.62))
            width: diameter
            height: diameter
            radius: diameter / 2

            anchors.right: trayIcon.right
            anchors.bottom: trayIcon.bottom

            color: Kirigami.Theme.negativeTextColor
            border.width: Math.max(1, Math.round(diameter * 0.08))
            border.color: Kirigami.Theme.backgroundColor

            Text {
                anchors.centerIn: parent
                text: root.lowCount
                color: "#ffffff"
                font.bold: true
                font.pixelSize: Math.max(6, Math.round(badge.diameter * 0.68))
                renderType: Text.NativeRendering
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12
        Layout.preferredWidth: Kirigami.Units.gridUnit * 21
        Layout.preferredHeight: Kirigami.Units.gridUnit * 15

        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 4
                    text: i18n("Peripheral Batteries")
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label {
                    text: root.lastUpdate
                    opacity: 0.6
                    font: Kirigami.Theme.smallFont
                }

                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    display: QQC2.AbstractButton.IconOnly
                    text: i18n("Refresh now")
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    onClicked: collectorSource.refresh()
                }
            }
        }

        contentItem: Item {
            PlasmaExtras.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                visible: root.everLoaded && root.devices.length === 0
                iconName: "battery-missing"
                text: i18n("No supported devices found")
                explanation: root.collectErrors.join("\n")
            }

            PlasmaComponents.ScrollView {
                anchors.fill: parent
                visible: root.devices.length > 0
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: root.devices

                        delegate: RowLayout {
                            required property var modelData

                            Layout.fillWidth: true
                            spacing: Kirigami.Units.largeSpacing

                            Kirigami.Icon {
                                source: root.kindIcon(modelData.kind)
                                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                                Layout.alignment: Qt.AlignVCenter
                                opacity: modelData.percent === null ? 0.5 : 1.0
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    elide: Text.ElideRight
                                }

                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: modelData.stale
                                          ? i18n("%1 · last read %2", modelData.status,
                                                 modelData.since)
                                          : modelData.status
                                    elide: Text.ElideRight
                                    opacity: 0.6
                                    font: Kirigami.Theme.smallFont
                                }

                                PlasmaComponents.ProgressBar {
                                    Layout.fillWidth: true
                                    Layout.topMargin: Kirigami.Units.smallSpacing
                                    visible: modelData.percent !== null
                                    from: 0
                                    to: 100
                                    value: modelData.percent || 0
                                }
                            }

                            PlasmaComponents.Label {
                                text: root.percentText(modelData)
                                horizontalAlignment: Text.AlignRight
                                Layout.alignment: Qt.AlignVCenter
                                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                                // A stale value is the last confirmed one, not a live read.
                                opacity: modelData.stale ? 0.6 : 1.0
                            }
                        }
                    }

                    Repeater {
                        model: root.collectErrors

                        delegate: RowLayout {
                            required property string modelData

                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Icon {
                                source: "dialog-warning"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                Layout.alignment: Qt.AlignTop
                            }

                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: modelData
                                wrapMode: Text.WordWrap
                                opacity: 0.7
                                font: Kirigami.Theme.smallFont
                            }
                        }
                    }
                }
            }
        }
    }
}
