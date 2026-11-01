// Close every Brave --app window pointed at the qBittorrent WebUI.
// The app_id is what Chromium derives from the --app URL's host and path; see
// the kwin-alttab-icon-appid note. Matching on it rather than on the title
// avoids touching ordinary Brave browser windows.
var APPID = "brave-127.0.0.1__-Default";
var list = (typeof workspace.windowList === "function")
           ? workspace.windowList() : workspace.clientList();
for (var i = 0; i < list.length; ++i) {
    var w = list[i];
    if (w.resourceClass === APPID)
        w.closeWindow();
}
