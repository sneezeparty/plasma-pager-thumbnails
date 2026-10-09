/*
    SPDX-FileCopyrightText: 2026 sneezeparty <38020091+sneezeparty@users.noreply.github.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import org.kde.plasma.plasmoid
import org.kde.taskmanager as TaskManager
import "Sources.js" as Sources

WallpaperItem {
    id: root

    // Each screen has its own wallpaper item, and can be on its own virtual desktop.
    readonly property string screenName: root.Screen.name ?? ""
    property string currentDesktop: ""
    readonly property var settings: Sources.parse(root.configuration.Settings)
    // Seconds since the epoch, refreshed now and then; folders move on when their interval rolls over.
    property real now: 0
    // desktop id -> url of the image to show there right now
    property var resolved: ({})
    // desktop id -> the pick a folder is on, and for which interval. Remembered across restarts:
    // a pick must hold until its interval is over, whatever happens to the folder meanwhile.
    property var picks: Sources.parseState(root.configuration.State)

    function updateCurrentDesktop() {
        const perScreen = root.screenName !== "" ? desktops.currentDesktopByScreenName(root.screenName) : undefined;
        root.currentDesktop = String(perScreen || desktops.currentDesktop || "");
    }

    function updateNow() {
        root.now = Math.floor(Date.now() / 1000);
        // Also a chance to put the published list right, should anything have replaced it
        publish.restart();
    }

    function setResolved(desktopId, url) {
        if (root.resolved[desktopId] === url) {
            return;
        }
        const copy = Object.assign({}, root.resolved);
        copy[desktopId] = url;
        root.resolved = copy;
        publish.restart();
    }

    function setPick(desktopId, pick) {
        const copy = Object.assign({}, root.picks);
        copy[desktopId] = pick;
        root.picks = copy;
        publish.restart();
    }

    onScreenNameChanged: updateCurrentDesktop()
    Component.onCompleted: {
        root.loading = true; // delays ksplash until the wallpaper has been loaded
        updateNow();
        updateCurrentDesktop();
    }

    // Nothing to show (an empty folder, a missing file): don't keep the login waiting for it
    Timer {
        interval: 3000
        running: root.loading
        onTriggered: root.loading = false
    }

    TaskManager.VirtualDesktopInfo {
        id: desktops
        onCurrentDesktopChanged: root.updateCurrentDesktop()
        onCurrentDesktopForScreenChanged: screenName => root.updateCurrentDesktop()
        onDesktopIdsChanged: root.updateCurrentDesktop()
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.updateNow()
    }

    // Tells the pager which image belongs to which desktop on this screen.
    Timer {
        id: publish
        interval: 200
        onTriggered: {
            const ids = desktops.desktopIds.map(id => String(id));
            const list = ids.filter(id => root.resolved[id]).map(id => id + "=" + root.resolved[id]);
            const picks = {};
            for (const id of ids) {
                if (root.picks[id]) {
                    picks[id] = root.picks[id];
                }
            }
            const state = JSON.stringify(picks);
            if (JSON.stringify(list) !== JSON.stringify(root.configuration.CurrentImages) || state !== root.configuration.State) {
                root.configuration.CurrentImages = list;
                root.configuration.State = state;
                root.configuration.writeConfig();
            }
        }
    }

    // One resolver per virtual desktop: turns its image-or-folder into the image to show.
    Repeater {
        model: desktops.desktopIds

        Item {
            id: resolver

            required property var modelData
            readonly property string desktopId: String(modelData)
            readonly property var entry: Sources.effective(root.settings, desktopId)
            readonly property bool isFolder: entry.mode === "folder" && entry.url !== ""
            property string image: ""

            function update() {
                // The pick depends on the screen, wait until it is known
                if (root.screenName === "") {
                    return;
                }
                if (!isFolder) {
                    image = entry.url;
                    return;
                }
                // While the folder is being read, what was shown before stays
                if (folder.status !== FolderListModel.Ready) {
                    return;
                }
                if (folder.count === 0) {
                    image = "";
                    return;
                }
                const tick = Sources.tick(entry, root.now);
                // Before picks were remembered, the image being shown was: carry on from it
                let pick = root.picks[desktopId];
                if (!pick) {
                    const shown = Sources.toMap(root.configuration.CurrentImages)[desktopId];
                    if (shown && folder.indexOf(shown) >= 0) {
                        pick = { url: shown, tick: tick, folder: entry.url, order: entry.order };
                        root.setPick(desktopId, pick);
                    }
                }
                const held = pick && pick.folder === entry.url ? folder.indexOf(pick.url) : -1;
                if (held >= 0 && pick.tick === tick && pick.order === entry.order) {
                    // Files coming and going (a synced folder) don't change the pick
                    image = pick.url;
                    return;
                }
                const index = Sources.next(entry, folder.count, root.screenName + desktopId, tick, held);
                image = String(folder.get(index, "fileUrl"));
                root.setPick(desktopId, { url: image, tick: tick, folder: entry.url, order: entry.order });
            }

            visible: false
            onEntryChanged: update()
            onImageChanged: root.setResolved(desktopId, image)
            Component.onCompleted: update()

            Connections {
                target: root
                function onNowChanged() { resolver.update(); }
                function onScreenNameChanged() { resolver.update(); }
            }

            FolderListModel {
                id: folder
                folder: resolver.isFolder ? resolver.entry.url : ""
                showDirs: false
                nameFilters: Sources.nameFilters
                caseSensitive: false
                sortField: FolderListModel.Name
                onStatusChanged: resolver.update()
                onCountChanged: resolver.update()
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.configuration.Color
    }

    // Two layers: the next image loads behind the scenes and is faded in once it is ready,
    // so switching desktops never shows a blank frame.
    readonly property string wanted: root.resolved[root.currentDesktop] ?? ""
    property Image front: layerA
    property Image back: layerB

    onWantedChanged: showWanted()
    onWidthChanged: showWanted()

    function showWanted() {
        // Without a size yet the image would be decoded at its full resolution
        if (root.wanted === "" || root.width <= 0 || root.height <= 0) {
            return;
        }
        if (root.front.wanted === root.wanted) {
            // Back to the image that is still up, whatever was being loaded meanwhile
            root.back.wanted = "";
            root.back.source = "";
            root.loading = false;
            return;
        }
        if (root.back.wanted === root.wanted) {
            root.swapWhenReady();
            return;
        }
        root.back.wanted = root.wanted;
        root.back.source = root.wanted;
        root.swapWhenReady();
    }

    function swapWhenReady() {
        const next = root.back;
        if (next.wanted !== root.wanted || next.status !== Image.Ready) {
            return;
        }
        root.back = root.front;
        root.front = next;
        root.front.z = 1;
        root.back.z = 0;
        root.front.visible = true;
        fade.target = root.front;
        fade.restart();
        root.loading = false;
        root.accentColorChanged();
    }

    component Layer: Image {
        // What `source` was set from. The source itself reads back in another spelling.
        property string wanted: ""

        anchors.fill: parent
        fillMode: root.configuration.FillMode
        asynchronous: true
        autoTransform: true
        cache: true
        smooth: true
        sourceSize: Qt.size(root.width * Screen.devicePixelRatio, root.height * Screen.devicePixelRatio)
        onStatusChanged: {
            if (status === Image.Ready) {
                root.swapWhenReady();
            } else if (status === Image.Error) {
                root.loading = false;
            }
        }
    }

    Layer { id: layerA }
    Layer { id: layerB }

    NumberAnimation {
        id: fade
        property: "opacity"
        from: 0
        to: 1
        duration: 200
        easing.type: Easing.InOutQuad
        // The image underneath would otherwise show around one that doesn't fill the screen
        onFinished: root.back.visible = false
    }
}
