/*
    SPDX-FileCopyrightText: 2026 sneezeparty <38020091+sneezeparty@users.noreply.github.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls
import org.kde.taskmanager as TaskManager
import "Sources.js" as Sources

ColumnLayout {
    id: root

    property string cfg_Settings
    property string cfg_SettingsDefault
    property int cfg_FillMode
    property int cfg_FillModeDefault
    property alias cfg_Color: colorButton.color
    property color cfg_ColorDefault
    // Handed over by the dialog: the wallpaper's live configuration, and the dialog itself.
    // CurrentImages deliberately has no cfg_ property: the wallpaper writes it, and the
    // dialog must not write an old copy back over it.
    property var wallpaperConfiguration: null
    property var configDialog: null

    property alias formLayout: appearanceForm

    readonly property var settings: Sources.parse(cfg_Settings)
    // What the wallpaper is showing on each desktop right now, used to preview folders.
    readonly property var currentImages: Sources.toMap(wallpaperConfiguration?.CurrentImages ?? [])
    // The desktop being edited; "" is the default that other desktops can follow.
    property string selected: ""
    readonly property bool selectedIsDefault: selected === ""
    readonly property bool selectedFollowsDefault: !selectedIsDefault && settings.desktops[selected] === undefined
    readonly property var selectedEntry: selectedIsDefault ? settings.default : Sources.effective(settings, selected)
    readonly property real screenRatio: Screen.width / Math.max(1, Screen.height)

    function desktopName(desktopId: string): string {
        if (desktopId === "") {
            return i18nc("@label the wallpaper used by desktops without their own", "Default");
        }
        const index = desktops.desktopIds.map(id => String(id)).indexOf(desktopId);
        return desktops.desktopNames[index] ?? i18n("Desktop %1", index + 1);
    }

    function save(model) {
        cfg_Settings = Sources.stringify(model);
    }

    // Changes some fields of a desktop's entry. A desktop that followed the default gets its
    // own entry, starting as a copy of the default.
    function change(desktopId: string, changes) {
        const model = Sources.parse(cfg_Settings);
        const base = desktopId === "" ? model.default : Sources.effective(model, desktopId);
        const entry = Sources.normalize(Object.assign({}, base, changes));
        if (desktopId === "") {
            model.default = entry;
        } else {
            model.desktops[desktopId] = entry;
        }
        save(model);
    }

    function followDefault(desktopId: string) {
        const model = Sources.parse(cfg_Settings);
        delete model.desktops[desktopId];
        save(model);
    }

    function copyToAll(desktopId: string) {
        const model = Sources.parse(cfg_Settings);
        const entry = desktopId === "" ? model.default : Sources.effective(model, desktopId);
        for (const id of desktops.desktopIds) {
            model.desktops[String(id)] = Sources.normalize(entry);
        }
        save(model);
    }

    function useImage(desktopId: string, url: string) {
        change(desktopId, { mode: "image", url: url });
    }

    function useFolder(desktopId: string, url: string) {
        change(desktopId, { mode: "folder", url: url.replace(/\/?$/, "/") });
    }

    // What a card or the panel shows for an entry: the image itself, or for a folder the
    // image the wallpaper currently has up, if it told us.
    function previewOf(desktopId: string, entry): string {
        if (entry.mode === "image") {
            return entry.url;
        }
        // What is up comes from the folder that was last applied. If another one has been
        // chosen since, it says nothing about that one.
        const fromFolder = url => url && entry.url !== "" && url.startsWith(entry.url) ? url : "";
        let shown = "";
        if (desktopId !== "") {
            shown = fromFolder(currentImages[desktopId]);
        } else {
            // The default has no desktop of its own; borrow one that follows it.
            for (const id of desktops.desktopIds) {
                if (settings.desktops[String(id)] === undefined && fromFolder(currentImages[String(id)])) {
                    shown = currentImages[String(id)];
                    break;
                }
            }
        }
        if (shown === "" && desktopId === selected && siblings.status === FolderListModel.Ready && siblings.count > 0) {
            // The folder is listed below for the desktop being edited: show its first image
            shown = String(siblings.get(0, "fileUrl"));
        }
        return shown;
    }

    function summaryOf(desktopId: string): string {
        if (desktopId !== "" && settings.desktops[desktopId] === undefined) {
            return i18nc("@info a desktop that uses the default wallpaper", "Same as Default");
        }
        const entry = desktopId === "" ? settings.default : settings.desktops[desktopId];
        if (entry.url === "") {
            return i18nc("@info", "Nothing chosen");
        }
        if (entry.mode === "image") {
            return i18nc("@info a single unchanging image", "One image");
        }
        return entry.order === "random" ? i18nc("@info", "Folder, random")
            : entry.order === "reverse" ? i18nc("@info", "Folder, reverse alphabetical")
            : i18nc("@info", "Folder, alphabetical");
    }

    spacing: Kirigami.Units.largeSpacing

    TaskManager.VirtualDesktopInfo {
        id: desktops
    }

    FileDialog {
        id: fileDialog
        title: i18nc("@title:window", "Choose an Image")
        nameFilters: [i18n("Images (%1)", Sources.nameFilters.join(" "))]
        onAccepted: root.useImage(root.selected, String(selectedFile))
    }

    FolderDialog {
        id: folderDialog
        title: i18nc("@title:window", "Choose a Folder of Images")
        onAccepted: root.useFolder(root.selected, String(selectedFolder))
    }

    // Everything sits in from the dialog's list of pages on the left
    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing * 2
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: root.spacing

        // ---- 1. Pick a desktop -------------------------------------------------------------

        Kirigami.Heading {
            level: 4
            text: i18nc("@title:group", "Virtual desktops on this screen")
        }

        component DesktopCard: QQC2.AbstractButton {
            id: card

            required property string desktopId
            readonly property var entry: desktopId === "" ? root.settings.default : Sources.effective(root.settings, desktopId)
            readonly property string preview: root.previewOf(desktopId, entry)
            readonly property bool current: root.selected === desktopId
            readonly property int previewHeight: Kirigami.Units.gridUnit * 5

            implicitWidth: Math.max(Kirigami.Units.gridUnit * 5, Math.round(previewHeight * root.screenRatio)) + Kirigami.Units.smallSpacing * 2
            implicitHeight: content.implicitHeight + Kirigami.Units.smallSpacing * 2
            padding: Kirigami.Units.smallSpacing
            onClicked: root.selected = desktopId

            Accessible.name: root.desktopName(desktopId)
            Accessible.description: root.summaryOf(desktopId)

            background: Rectangle {
                radius: Kirigami.Units.cornerRadius
                color: card.current ? Qt.alpha(Kirigami.Theme.highlightColor, 0.2)
                     : card.hovered ? Qt.alpha(Kirigami.Theme.textColor, 0.06) : "transparent"
                border.width: card.current || card.visualFocus ? 2 : 0
                border.color: Kirigami.Theme.highlightColor
            }

            contentItem: ColumnLayout {
                id: content
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredHeight: card.previewHeight
                    Layout.preferredWidth: Math.round(card.previewHeight * root.screenRatio)
                    color: root.cfg_Color
                    border.width: 1
                    border.color: Qt.alpha(Kirigami.Theme.textColor, 0.25)
                    radius: Kirigami.Units.cornerRadius / 2
                    clip: true

                    Image {
                        anchors.fill: parent
                        anchors.margins: 1
                        source: card.preview
                        sourceSize: Qt.size(width * 2, height * 2)
                        fillMode: root.cfg_FillMode === Image.Tile ? Image.PreserveAspectCrop : root.cfg_FillMode
                        asynchronous: true
                        cache: true
                    }

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: Kirigami.Units.iconSizes.medium
                        height: width
                        visible: card.preview === ""
                        source: card.entry.url === "" ? "edit-none" : "folder-pictures"
                        opacity: 0.7
                    }

                    // Says at a glance that this desktop rotates through a folder
                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Kirigami.Units.smallSpacing
                        width: badge.width + Kirigami.Units.smallSpacing
                        height: width
                        radius: width / 2
                        color: Qt.alpha(Kirigami.Theme.backgroundColor, 0.85)
                        visible: card.entry.mode === "folder" && card.entry.url !== "" && card.preview !== ""

                        Kirigami.Icon {
                            id: badge
                            anchors.centerIn: parent
                            width: Kirigami.Units.iconSizes.small
                            height: width
                            source: card.entry.order === "random" ? "media-playlist-shuffle" : "media-playlist-repeat"
                        }
                    }

                    DropArea {
                        anchors.fill: parent
                        keys: ["text/uri-list"]
                        onDropped: drop => {
                            if (!drop.hasUrls || drop.urls.length === 0) {
                                return;
                            }
                            const url = String(drop.urls[0]);
                            root.selected = card.desktopId;
                            if (Sources.isImage(url)) {
                                root.useImage(card.desktopId, url);
                            } else if (!/\.[A-Za-z0-9]{1,5}$/.test(url.replace(/\/$/, ""))) {
                                // Not an image, and it doesn't look like another kind of file either
                                root.useFolder(card.desktopId, url);
                            }
                        }
                    }
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.desktopName(card.desktopId)
                    elide: Text.ElideRight
                    font.weight: card.current ? Font.DemiBold : Font.Normal
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.summaryOf(card.desktopId)
                    elide: Text.ElideRight
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: desktops.desktopIds

                DesktopCard {
                    required property var modelData
                    desktopId: String(modelData)
                }
            }

            Kirigami.Separator {
                width: 1
                height: defaultCard.height
            }

            DesktopCard {
                id: defaultCard
                desktopId: ""
            }
        }

        // ---- 2. Say what the selected desktop shows ----------------------------------------

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Kirigami.Heading {
            level: 4
            text: root.selectedIsDefault
                ? i18nc("@title:group", "Default, for desktops set to \"Same as Default\"")
                : root.desktopName(root.selected)
        }

        Kirigami.FormLayout {
            id: sourceForm
            Layout.fillWidth: true

            QQC2.ButtonGroup {
                id: modeGroup
            }

            QQC2.RadioButton {
                Kirigami.FormData.label: i18nc("@title:group prefix for radio buttons", "Show:")
                visible: !root.selectedIsDefault
                QQC2.ButtonGroup.group: modeGroup
                text: i18nc("@option:radio", "Same as Default")
                checked: root.selectedFollowsDefault
                onToggled: if (checked) root.followDefault(root.selected)
            }

            QQC2.RadioButton {
                Kirigami.FormData.label: root.selectedIsDefault ? i18nc("@title:group prefix for radio buttons", "Show:") : ""
                QQC2.ButtonGroup.group: modeGroup
                text: i18nc("@option:radio", "Single image")
                checked: !root.selectedFollowsDefault && root.selectedEntry.mode === "image"
                onToggled: if (checked) root.change(root.selected, {
                    mode: "image",
                    // Start from what is on screen now, if this desktop was showing a folder
                    url: Sources.isImage(root.selectedEntry.url) ? root.selectedEntry.url : root.previewOf(root.selected, root.selectedEntry),
                })
            }

            QQC2.RadioButton {
                QQC2.ButtonGroup.group: modeGroup
                text: i18nc("@option:radio", "Folder of images")
                checked: !root.selectedFollowsDefault && root.selectedEntry.mode === "folder"
                onToggled: if (checked) root.change(root.selected, { mode: "folder", url: Sources.folderOf(root.selectedEntry) })
            }

            Item {
                Kirigami.FormData.isSection: true
                visible: !root.selectedFollowsDefault
            }

            RowLayout {
                Kirigami.FormData.label: root.selectedEntry.mode === "image" ? i18nc("@label", "Image:") : i18nc("@label", "Folder:")
                visible: !root.selectedFollowsDefault
                spacing: Kirigami.Units.smallSpacing

                QQC2.TextField {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 18
                    readOnly: true
                    text: Sources.path(root.selectedEntry.url)
                    placeholderText: i18nc("@info:placeholder", "Nothing chosen yet")
                }

                QQC2.Button {
                    icon.name: root.selectedEntry.mode === "image" ? "viewimage" : "folder-open"
                    text: i18nc("@action:button", "Choose…")
                    onClicked: {
                        const dialog = root.selectedEntry.mode === "image" ? fileDialog : folderDialog;
                        const folder = Sources.folderOf(root.selectedEntry);
                        if (folder !== "") {
                            dialog.currentFolder = folder;
                        }
                        dialog.open();
                    }
                }
            }

            QQC2.ComboBox {
                Kirigami.FormData.label: i18nc("@label:listbox", "Order:")
                visible: !root.selectedFollowsDefault && root.selectedEntry.mode === "folder"
                textRole: "label"
                valueRole: "order"
                model: [
                    { label: i18nc("@item:inlistbox", "Random"), order: "random" },
                    { label: i18nc("@item:inlistbox", "Alphabetical order"), order: "sequential" },
                    { label: i18nc("@item:inlistbox", "Reverse alphabetical order"), order: "reverse" },
                ]
                currentIndex: Math.max(0, model.findIndex(item => item.order === root.selectedEntry.order))
                onActivated: root.change(root.selected, { order: currentValue })
            }

            RowLayout {
                id: intervalRow
                Kirigami.FormData.label: i18nc("@label:spinbox", "Change every:")
                visible: !root.selectedFollowsDefault && root.selectedEntry.mode === "folder"
                spacing: Kirigami.Units.smallSpacing

                readonly property var units: [60, 3600, 86400]
                // The unit that was last chosen here, as long as it fits; 120 minutes stay minutes
                // while stepping through them. Otherwise the largest unit that divides the interval evenly.
                property int chosenUnit: -1
                readonly property int unitIndex: chosenUnit >= 0 && root.selectedEntry.interval % units[chosenUnit] === 0 ? chosenUnit
                                               : root.selectedEntry.interval % 86400 === 0 ? 2
                                               : root.selectedEntry.interval % 3600 === 0 ? 1 : 0

                Connections {
                    target: root
                    function onSelectedChanged() { intervalRow.chosenUnit = -1; }
                }

                QQC2.SpinBox {
                    id: intervalSpin
                    from: 1
                    to: 999
                    value: Math.max(1, Math.round(root.selectedEntry.interval / intervalRow.units[intervalRow.unitIndex]))
                    onValueModified: {
                        intervalRow.chosenUnit = unitBox.currentIndex;
                        root.change(root.selected, { interval: value * intervalRow.units[unitBox.currentIndex] });
                    }
                }

                QQC2.ComboBox {
                    id: unitBox
                    model: [
                        i18nc("@item:inlistbox unit after a number", "minutes"),
                        i18nc("@item:inlistbox unit after a number", "hours"),
                        i18nc("@item:inlistbox unit after a number", "days"),
                    ]
                    currentIndex: intervalRow.unitIndex
                    onActivated: {
                        intervalRow.chosenUnit = currentIndex;
                        root.change(root.selected, { interval: intervalSpin.value * intervalRow.units[currentIndex] });
                    }
                }
            }
        }

        // ---- 3. How images are fitted, for every desktop on this screen ---------------------

        Kirigami.FormLayout {
            id: appearanceForm
            twinFormLayouts: [sourceForm]
            Layout.fillWidth: true

            QQC2.ComboBox {
                Kirigami.FormData.label: i18nc("@label:listbox", "Positioning:")
                textRole: "label"
                valueRole: "mode"
                model: [
                    { label: i18nc("@item:inlistbox", "Scaled and Cropped"), mode: Image.PreserveAspectCrop },
                    { label: i18nc("@item:inlistbox", "Scaled, Keep Proportions"), mode: Image.PreserveAspectFit },
                    { label: i18nc("@item:inlistbox", "Scaled"), mode: Image.Stretch },
                    { label: i18nc("@item:inlistbox", "Centered"), mode: Image.Pad },
                    { label: i18nc("@item:inlistbox", "Tiled"), mode: Image.Tile },
                ]
                currentIndex: Math.max(0, model.findIndex(item => item.mode === root.cfg_FillMode))
                onActivated: root.cfg_FillMode = currentValue
            }

            KQuickControls.ColorButton {
                id: colorButton
                Kirigami.FormData.label: i18nc("@label:chooser", "Background color:")
                dialogTitle: i18nc("@title:window", "Select Background Color")
            }

            // No label: lines up with the fields above
            QQC2.Button {
                icon.name: "edit-copy"
                text: root.selectedIsDefault
                    ? i18nc("@action:button", "Use the Default on Every Desktop")
                    : i18nc("@action:button %1 is the name of a virtual desktop", "Use %1's Setting on Every Desktop", root.desktopName(root.selected))
                visible: desktops.desktopIds.length > 1 && !root.selectedFollowsDefault
                onClicked: root.selectedIsDefault ? desktops.desktopIds.forEach(id => root.followDefault(String(id))) : root.copyToAll(root.selected)
            }
        }

        // ---- 4. The images next to the chosen one, or inside the chosen folder. In "one image" mode
        // clicking one picks it, which is quicker than the file dialog.
        FolderListModel {
            id: siblings
            folder: root.selectedFollowsDefault ? "" : Sources.folderOf(root.selectedEntry)
            showDirs: false
            nameFilters: Sources.nameFilters
            caseSensitive: false
            sortField: FolderListModel.Name
        }

        QQC2.Label {
            Layout.fillWidth: true
            visible: thumbnails.visible
            wrapMode: Text.Wrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            text: root.selectedEntry.mode === "image"
                ? i18ncp("@info", "%1 image in the same folder. Click one to use it.", "%1 images in the same folder. Click one to use it.", siblings.count)
                : i18ncp("@info", "%1 image in this folder.", "%1 images in this folder.", siblings.count)
        }

        ListView {
            id: thumbnails

            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 5 + Kirigami.Units.largeSpacing * 2
            visible: !root.selectedFollowsDefault && String(siblings.folder) !== "" && siblings.count > 0
            orientation: ListView.Horizontal
            spacing: Kirigami.Units.smallSpacing
            model: siblings
            clip: true
            // Only decode what is near the visible part; folders can hold hundreds of images
            cacheBuffer: width
            boundsBehavior: Flickable.StopAtBounds

            QQC2.ScrollBar.horizontal: QQC2.ScrollBar {}

            delegate: QQC2.AbstractButton {
                id: thumb

                required property url fileUrl
                required property string fileName
                readonly property bool shown: String(fileUrl) === root.previewOf(root.selected, root.selectedEntry)

                height: ListView.view.height - Kirigami.Units.largeSpacing * 1.5
                width: Math.round(height * root.screenRatio)
                enabled: root.selectedEntry.mode === "image"
                onClicked: root.useImage(root.selected, String(fileUrl))

                Accessible.name: fileName
                QQC2.ToolTip.text: fileName
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

                background: Rectangle {
                    color: root.cfg_Color
                    radius: Kirigami.Units.cornerRadius / 2
                    border.width: thumb.shown ? 2 : 1
                    border.color: thumb.shown ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.textColor, 0.25)
                }

                contentItem: Item {
                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: thumb.fileUrl
                        sourceSize: Qt.size(width * 2, height * 2)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }
            }
        }
    }

    Item {
        Layout.fillHeight: true
    }

    Component.onCompleted: {
        // Open on the desktop this screen is showing
        const current = desktops.currentDesktopByScreenName(Screen.name) || desktops.currentDesktop;
        root.selected = current ? String(current) : "";
    }
}
