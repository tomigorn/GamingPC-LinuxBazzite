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

    // qbittorrent-nox runs headless in a container and cannot own a tray icon
    // the way the Windows GUI client does. This widget stands in for it; the
    // state comes from systemd and podman, never from qBittorrent itself.
    readonly property string statusCmd: "/home/bazzite/.local/bin/qbit-vpn-status"
    readonly property string launcher: "/home/bazzite/.local/share/qbit-vpn/launch.sh"

    property string gluetun: ""
    property string qbit: ""
    property string health: ""
    property string fwdPort: ""
    property string country: ""
    property string exitIp: ""
    property real dlSpeed: 0
    property real upSpeed: 0
    property real dlData: 0
    property real upData: 0
    property string conn: ""
    property int torrentsTotal: 0
    property int torrentsActive: 0
    property string realIp: ""
    property string ext4: ""
    property string ext6: ""
    property real allDl: 0
    property real allUp: 0
    property real ratio: 0
    property var downloads: []
    property int compCount: -1          // -1 = not yet read, so startup never notifies
    property string compLast: ""
    // Rolling speed history for the sparkline. Only fills while the panel is
    // open, because that is the only time speeds are polled.
    property var dlHistory: []
    property var upHistory: []
    readonly property int historyLen: 60

    // THE test. Both values come from independent sources: ext4 is what trackers
    // and peers report back to qBittorrent, realIp is fetched over the normal
    // route outside the tunnel. If they are equal, the traffic is not tunnelled.
    readonly property bool leaking: ext4.length > 0 && realIp.length > 0
                                    && ext4 === realIp
    readonly property bool ipsProven: ext4.length > 0 && realIp.length > 0
                                      && ext4 !== realIp

    // Proton can egress on a different address than the one its IP API reports,
    // so a mismatch is "look into this", not a proven leak. verify.sh settles it
    // by comparing against this machine's real IP.
    readonly property bool addrMismatch: ext4.length > 0 && exitIp.length > 0
                                         && ext4 !== exitIp
    property bool everLoaded: false
    property bool stopping: false

    // The whole point of the widget: this must be true ONLY when the traffic is
    // genuinely tunnelled. Every condition is required.
    //   health === healthy  gluetun's own check, which probes THROUGH the tunnel
    //   qbit   === active   qBittorrent exists, inside gluetun's netns
    //   exitIp !== ""       gluetun resolved a public IP from inside the tunnel
    // Anything less is never reported as protected.
    readonly property bool protected_: gluetun === "active" && health === "healthy"
                                       && qbit === "active" && exitIp !== ""
                                       && !leaking

    readonly property bool live: gluetun === "active" || gluetun === "activating"

    readonly property string vpnState: {
        if (!everLoaded)
            return "unknown";
        if (leaking)
            return "leak";
        if (stopping)
            return "stopping";
        if (protected_)
            return "up";
        if (gluetun === "activating" || health === "starting"
                || (gluetun === "active" && qbit !== "active"))
            return "connecting";
        if (gluetun === "active" && health === "unhealthy")
            return "degraded";
        if (gluetun === "failed")
            return "failed";
        return "stopped";
    }

    function stateLabel() {
        switch (vpnState) {
        case "up":         return ipsProven
                                  ? i18n("Active — behind ProtonVPN (verified)")
                                  : i18n("Active — behind ProtonVPN");
        case "leak":       return i18n("NOT PROTECTED — peers see your real IP");
        case "connecting": return i18n("Connecting…");
        case "stopping":   return i18n("Stopping…");
        case "degraded":   return i18n("Tunnel unhealthy — shutting down");
        case "failed":     return i18n("VPN failed — qBittorrent not started");
        case "stopped":    return i18n("Stopped");
        default:           return i18n("Checking…");
        }
    }

    function stateColor() {
        switch (vpnState) {
        case "up":         return Kirigami.Theme.positiveTextColor;
        case "connecting":
        case "stopping":   return Kirigami.Theme.neutralTextColor;
        case "degraded":
        case "failed":
        case "leak":       return Kirigami.Theme.negativeTextColor;
        default:           return Kirigami.Theme.disabledTextColor;
        }
    }

    // Out of the way when there is nothing running, present the moment there is.
    Plasmoid.status: live || stopping ? PlasmaCore.Types.ActiveStatus
                                      : PlasmaCore.Types.PassiveStatus

    Plasmoid.icon: "qbittorrent"

    Plasma5Support.DataSource {
        id: statusSource
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            disconnectSource(source);
            var out = (data["stdout"] || "").trim();
            if (out.length === 0)
                return;
            try {
                var s = JSON.parse(out);
                root.gluetun = s.gluetun || "";
                root.qbit = s.qbit || "";
                root.health = s.health || "";
                root.fwdPort = s.port || "";
                root.country = s.country || "";
                root.exitIp = s.ip || "";
                root.dlSpeed = s.dl || 0;
                root.upSpeed = s.up || 0;
                root.dlData = s.dld || 0;
                root.upData = s.upd || 0;
                root.conn = s.conn || "";
                root.torrentsTotal = s.total || 0;
                root.torrentsActive = s.active || 0;
                root.realIp = s.realip || "";
                root.ext4 = s.ext4 || "";
                root.ext6 = s.ext6 || "";
                root.allDl = s.alldl || 0;
                root.allUp = s.allup || 0;
                root.ratio = s.ratio || 0;
                root.downloads = s.downloads || [];

                // Torrent finished: the count only ever grows, and starting at
                // -1 means the first poll after login seeds it without firing
                // a notification for everything downloaded previously.
                var newCount = s.compcount || 0;
                if (root.compCount >= 0 && newCount > root.compCount) {
                    var extra = newCount - root.compCount;
                    root.notify(i18np("Download finished", "%1 downloads finished", extra),
                                s.complast || "", "qbittorrent", false);
                }
                root.compCount = newCount;
                root.compLast = s.complast || "";

                if (root.expanded) {
                    var dh = root.dlHistory.slice();
                    var uh = root.upHistory.slice();
                    dh.push(root.dlSpeed); uh.push(root.upSpeed);
                    while (dh.length > root.historyLen) dh.shift();
                    while (uh.length > root.historyLen) uh.shift();
                    root.dlHistory = dh; root.upHistory = uh;
                }
                root.everLoaded = true;
                if (root.gluetun === "inactive" || root.gluetun === "failed")
                    root.stopping = false;
            } catch (e) {
                // Keep the previous values rather than flashing a wrong state on
                // one malformed read.
            }
        }

        // The --stats form costs a podman exec, so it is only used while the
        // panel is actually on screen.
        function refresh() {
            var cmd = root.expanded ? root.statusCmd + " --stats" : root.statusCmd;
            disconnectSource(cmd);
            connectSource(cmd);
        }
    }

    // Separate source so command output never reaches the JSON parser above.
    Plasma5Support.DataSource {
        id: shell
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            disconnectSource(source);
            statusSource.refresh();
        }
        function exec(cmd) {
            disconnectSource(cmd);
            connectSource(cmd);
        }
    }

    function notify(title, body, icon, critical) {
        shell.exec("notify-send -a qBittorrent -i " + (icon || "qbittorrent")
                   + (critical ? " -u critical " : " ")
                   + "'" + String(title).replace(/'/g, "") + "' "
                   + "'" + String(body).replace(/'/g, "") + "'");
    }

    function doMagnet() {
        shell.exec("/home/bazzite/.local/share/qbit-vpn/add-magnet.sh");
    }

    function doOpen() {
        shell.exec(launcher);
    }

    // Stop gluetun, not qBittorrent: BindsTo= in qbittorrent.container takes
    // qBittorrent down with the namespace it lives in. Stopping qBittorrent
    // alone would leave the tunnel up doing nothing.
    // Close the WebUI window(s) first: leaving a browser window behind showing a
    // dead page reads as "still running". Sequenced with ';' so the stop happens
    // even if the window close fails.
    function doStop() {
        stopping = true;
        shell.exec("/home/bazzite/.local/share/qbit-vpn/close-webui.sh; " +
                   "systemctl --user stop gluetun.service");
    }

    // Opening the panel should show live figures at once, not after the next tick.
    onExpandedChanged: statusSource.refresh()

    function fmtBytes(n) {
        if (!n || n < 1) return "0 B";
        var u = ["B", "KiB", "MiB", "GiB", "TiB"], i = 0;
        while (n >= 1024 && i < u.length - 1) { n /= 1024; ++i; }
        return (i === 0 ? Math.round(n) : n.toFixed(1)) + " " + u[i];
    }
    function fmtSpeed(n) {
        return fmtBytes(n) + "/s";
    }
    // qBittorrent reports 8640000 for "unknown"; the collector maps that to 0.
    function fmtEta(sec) {
        if (!sec || sec <= 0) return i18n("unknown");
        if (sec < 60) return i18n("%1s", Math.round(sec));
        if (sec < 3600) return i18n("%1m", Math.round(sec / 60));
        if (sec < 86400) {
            var h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
            return m > 0 ? i18n("%1h %2m", h, m) : i18n("%1h", h);
        }
        return i18n("%1d %2h", Math.floor(sec / 86400),
                    Math.round((sec % 86400) / 3600));
    }

    property string prevState: ""
    onVpnStateChanged: {
        // A clean "inactive" means someone pressed Stop; an auto-restart leaves
        // gluetun activating/failed, which is the case worth shouting about.
        if (prevState === "up" && vpnState !== "up" && !stopping
                && gluetun !== "inactive") {
            notify(i18n("ProtonVPN tunnel dropped"),
                   i18n("qBittorrent was stopped. It will come back when the tunnel does."),
                   "network-disconnect", true);
        }
        prevState = vpnState;
    }

    onLeakingChanged: {
        if (leaking && !stopping) {
            shell.exec("notify-send -u critical -a qBittorrent -i qbittorrent " +
                       "'qBittorrent stopped: VPN leak' " +
                       "'Peers were seeing your real IP address, so the stack was shut down.'");
            doStop();
        }
    }

    Timer {
        interval: root.expanded ? 2000
                : (root.vpnState === "connecting" || root.stopping ? 2000 : 6000)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: statusSource.refresh()
    }

    toolTipMainText: i18n("qBittorrent")
    toolTipSubText: {
        var lines = [stateLabel()];
        if (protected_) {
            lines.push(i18n("Exit IP: %1 (%2)", exitIp, country));
            lines.push(fwdPort.length > 0 ? i18n("Forwarded port: %1", fwdPort)
                                          : i18n("No forwarded port"));
        }
        return lines.join("\n");
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("@action", "Show WebUI")
            icon.name: "qbittorrent"
            onTriggered: root.doOpen()
        },
        PlasmaCore.Action {
            text: i18nc("@action", "Add magnet from clipboard")
            icon.name: "edit-paste"
            enabled: root.running
            onTriggered: root.doMagnet()
        },
        PlasmaCore.Action {
            text: i18nc("@action", "Stop qBittorrent and VPN")
            icon.name: "process-stop"
            enabled: root.live && !root.stopping
            onTriggered: root.doStop()
        }
    ]

    compactRepresentation: MouseArea {
        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onClicked: function (mouse) {
            if (mouse.button === Qt.MiddleButton)
                root.doOpen();
            else
                root.expanded = !root.expanded;
        }

        Kirigami.Icon {
            id: trayIcon
            anchors.fill: parent
            source: "qbittorrent-tray"
            active: parent.containsMouse
            opacity: root.protected_ ? 1.0 : 0.5
        }

        Rectangle {
            id: dot
            z: 1
            readonly property int diameter: Math.max(Kirigami.Units.gridUnit * 0.42,
                                                     Math.round(Math.min(trayIcon.width,
                                                                         trayIcon.height) * 0.4))
            width: diameter
            height: diameter
            radius: diameter / 2
            anchors.right: trayIcon.right
            anchors.bottom: trayIcon.bottom
            color: root.stateColor()
            border.width: Math.max(1, Math.round(diameter * 0.12))
            border.color: Kirigami.Theme.backgroundColor

            SequentialAnimation on opacity {
                running: root.vpnState === "connecting" || root.stopping
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { from: 1.0; to: 0.3; duration: 700 }
                NumberAnimation { from: 0.3; to: 1.0; duration: 700 }
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 15
        Layout.preferredWidth: Kirigami.Units.gridUnit * 19
        Layout.preferredHeight: Kirigami.Units.gridUnit * 26

        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "qbittorrent"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                }
                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 4
                    text: i18n("qBittorrent")
                    elide: Text.ElideRight
                }
            }
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 0.6
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 0.6
                    radius: width / 2
                    color: root.stateColor()
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.stateLabel()
                    wrapMode: Text.WordWrap
                    font.bold: true
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                visible: root.protected_
                columns: 2
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label { text: i18n("This machine"); opacity: 0.7 }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.realIp.length > 0 ? root.realIp : "—"
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label { text: i18n("Tunnel exit"); opacity: 0.7 }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.exitIp + (root.country.length > 0
                                         ? " (" + root.country + ")" : "")
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label { text: i18n("Seen by peers"); opacity: 0.7 }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    // Empty until a tracker or peer has reported it back.
                    text: root.ext4.length > 0
                          ? root.ext4 + (root.ipsProven ? i18n("  ✓ differs") : "")
                          : i18n("— not known yet")
                    color: root.leaking ? Kirigami.Theme.negativeTextColor
                         : root.ipsProven ? Kirigami.Theme.positiveTextColor
                         : Kirigami.Theme.textColor
                    font.bold: root.leaking
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label {
                    text: i18n("IPv6 seen")
                    opacity: 0.7
                    visible: root.ext6.length > 0
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    visible: root.ext6.length > 0
                    // The Proton tunnel here is IPv4; any v6 address peers can
                    // see is worth questioning.
                    text: root.ext6
                    color: Kirigami.Theme.neutralTextColor
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label { text: i18n("Forwarded port"); opacity: 0.7 }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.fwdPort.length > 0 ? root.fwdPort : i18n("none")
                    color: root.fwdPort.length > 0 ? Kirigami.Theme.textColor
                                                   : Kirigami.Theme.neutralTextColor
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label { text: i18n("Peers"); opacity: 0.7 }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.conn.length > 0 ? root.conn : "—"
                    // "firewalled" with nothing running is normal and not worth
                    // flagging; it only means something once a torrent is active.
                    color: (root.conn === "firewalled" && root.torrentsActive > 0)
                           ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                    elide: Text.ElideRight
                }

                Kirigami.Separator { Layout.fillWidth: true; Layout.columnSpan: 2 }

                PlasmaComponents.Label { text: i18n("Download"); opacity: 0.7 }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.fmtSpeed(root.dlSpeed)
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label { text: i18n("Upload"); opacity: 0.7 }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.fmtSpeed(root.upSpeed)
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label { text: i18n("Torrents"); opacity: 0.7 }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: i18n("%1 active / %2", root.torrentsActive, root.torrentsTotal)
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label { text: i18n("This session"); opacity: 0.7 }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: "\u2193 " + root.fmtBytes(root.dlData)
                          + "   \u2191 " + root.fmtBytes(root.upData)
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label { text: i18n("All time"); opacity: 0.7 }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: "\u2193 " + root.fmtBytes(root.allDl)
                          + "   \u2191 " + root.fmtBytes(root.allUp)
                          + (root.ratio > 0 ? i18n("   ratio %1", root.ratio) : "")
                    elide: Text.ElideRight
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                visible: root.addrMismatch
                text: i18n("Peers see a different address than the tunnel reports. Run verify.sh to check against your real IP.")
                color: Kirigami.Theme.neutralTextColor
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
            }

            // Speed sparkline: download filled, upload as a line over it. Both
            // share one vertical scale so their relative size stays honest.
            Canvas {
                id: spark
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                visible: root.dlHistory.length > 1

                readonly property color dlColor: Kirigami.Theme.highlightColor
                readonly property color upColor: Kirigami.Theme.positiveTextColor

                // Repaint whenever a new sample lands.
                Connections {
                    target: root
                    function onDlHistoryChanged() { spark.requestPaint(); }
                }

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var w = width, h = height;
                    var dl = root.dlHistory, up = root.upHistory;
                    if (dl.length < 2)
                        return;

                    var peak = 1;
                    for (var i = 0; i < dl.length; ++i) {
                        if (dl[i] > peak) peak = dl[i];
                        if (up[i] > peak) peak = up[i];
                    }
                    // Headroom so a flat line does not sit on the very top edge.
                    peak *= 1.15;

                    var stepX = w / (root.historyLen - 1);
                    // Right-align: a partly filled history grows from the right.
                    var offset = w - (dl.length - 1) * stepX;
                    function xy(arr, i) {
                        return [offset + i * stepX, h - (arr[i] / peak) * h];
                    }

                    // Download: filled area.
                    ctx.beginPath();
                    ctx.moveTo(offset, h);
                    for (var j = 0; j < dl.length; ++j) {
                        var p1 = xy(dl, j);
                        ctx.lineTo(p1[0], p1[1]);
                    }
                    ctx.lineTo(w, h);
                    ctx.closePath();
                    ctx.fillStyle = Qt.rgba(dlColor.r, dlColor.g, dlColor.b, 0.30);
                    ctx.fill();

                    ctx.beginPath();
                    for (var k = 0; k < dl.length; ++k) {
                        var p2 = xy(dl, k);
                        if (k === 0) ctx.moveTo(p2[0], p2[1]); else ctx.lineTo(p2[0], p2[1]);
                    }
                    ctx.strokeStyle = dlColor;
                    ctx.lineWidth = 1.5;
                    ctx.stroke();

                    // Upload: line only.
                    ctx.beginPath();
                    for (var m = 0; m < up.length; ++m) {
                        var p3 = xy(up, m);
                        if (m === 0) ctx.moveTo(p3[0], p3[1]); else ctx.lineTo(p3[0], p3[1]);
                    }
                    ctx.strokeStyle = upColor;
                    ctx.lineWidth = 1.5;
                    ctx.stroke();
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                visible: spark.visible
                horizontalAlignment: Text.AlignRight
                font: Kirigami.Theme.smallFont
                opacity: 0.6
                text: i18n("last %1s  ·  peak %2",
                           root.dlHistory.length * 2,
                           root.fmtSpeed(Math.max.apply(null,
                               root.dlHistory.concat(root.upHistory).concat([0]))))
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                visible: root.downloads.length > 0
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing
                visible: root.downloads.length > 0

                Repeater {
                    model: root.downloads

                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 2

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: modelData.name
                            elide: Text.ElideMiddle
                            font: Kirigami.Theme.smallFont
                        }

                        PlasmaComponents.ProgressBar {
                            Layout.fillWidth: true
                            from: 0
                            to: 100
                            value: modelData.progress
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            PlasmaComponents.Label {
                                text: i18n("%1%", modelData.progress)
                                font: Kirigami.Theme.smallFont
                                opacity: 0.8
                            }
                            Item { Layout.fillWidth: true }
                            PlasmaComponents.Label {
                                text: modelData.dlspeed > 0
                                      ? root.fmtSpeed(modelData.dlspeed) + "  \u00b7  "
                                        + i18n("%1 left", root.fmtEta(modelData.eta))
                                      : i18n("stalled")
                                font: Kirigami.Theme.smallFont
                                opacity: 0.8
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Button {
                    Layout.fillWidth: true
                    icon.name: "qbittorrent"
                    text: i18n("Show WebUI")
                    onClicked: {
                        root.doOpen();
                        root.expanded = false;
                    }
                }
                // Icon-only: three full-width text buttons do not fit the panel,
                // and this is the one whose icon reads unambiguously.
                PlasmaComponents.Button {
                    icon.name: "edit-paste"
                    display: QQC2.AbstractButton.IconOnly
                    text: i18n("Add magnet from clipboard")
                    enabled: root.running
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    onClicked: {
                        root.doMagnet();
                        root.expanded = false;
                    }
                }

                PlasmaComponents.Button {
                    Layout.fillWidth: true
                    icon.name: "process-stop"
                    text: i18n("Stop")
                    enabled: root.live && !root.stopping
                    onClicked: {
                        root.doStop();
                        root.expanded = false;
                    }
                }
            }
        }
    }
}
