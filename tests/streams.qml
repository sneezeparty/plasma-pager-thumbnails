// Protocol test without the pager: one scaled stream per virtual desktop, plus a
// scaled and a native stream of the first window, saved to streams.png after a few seconds.
//   source ~/kde/nested-home/env.sh && qml ~/kde/tests/streams.qml
import QtQuick
import QtQuick.Window
import org.kde.pipewire as PipeWire
import org.kde.taskmanager as TaskManager

Window {
    id: win
    width: column.width; height: column.height
    visible: true
    color: "#202020"
    title: "stream test"

    TaskManager.VirtualDesktopInfo { id: desktops }
    TaskManager.TasksModel { id: tasks; filterByVirtualDesktop: false; filterByActivity: false; groupMode: TaskManager.TasksModel.GroupDisabled }

    component Stream: PipeWire.PipeWireSourceItem {
        id: item
        property string label
        property alias request: request
        width: 320; height: 180
        nodeId: request.nodeId
        onStreamSizeChanged: console.log("RESULT", label, "buffer", streamSize.width + "x" + streamSize.height,
                                         "=", Math.round(streamSize.width * streamSize.height * 4 / 1024), "KiB")
        TaskManager.ScreencastingRequest { id: request }
    }

    Column {
        id: column
        spacing: 8
        Row {
            spacing: 8
            Repeater {
                model: desktops.desktopIds
                Stream {
                    required property string modelData
                    required property int index
                    label: "desktop" + (index + 1)
                    request.desktopId: modelData
                    request.maxSize: Qt.size(320, 180)
                }
            }
        }
        Row {
            // Desktop 2 again, limited to each screen in turn
            spacing: 8
            Repeater {
                model: Qt.application.screens
                Stream {
                    required property var modelData
                    width: 320; height: 320
                    label: "desktop2-on-" + modelData.name
                    request.desktopId: desktops.desktopIds[1] ?? ""
                    request.outputName: modelData.name
                    request.maxSize: Qt.size(320, 320)
                }
            }
        }
        Row {
            spacing: 8
            Repeater {
                model: tasks.count > 0 ? 1 : 0
                Stream {
                    label: "window-scaled"
                    request.uuid: tasks.data(tasks.index(0, 0), TaskManager.AbstractTasksModel.WinIdList)[0]
                    request.maxSize: Qt.size(320, 180)
                }
            }
            Repeater {
                model: tasks.count > 0 ? 1 : 0
                Stream {
                    label: "window-native"
                    request.uuid: tasks.data(tasks.index(0, 0), TaskManager.AbstractTasksModel.WinIdList)[0]
                }
            }
        }
    }

    Timer {
        interval: 6000; running: true
        onTriggered: column.grabToImage(result => {
            console.log("RESULT saved", result.saveToFile(Qt.resolvedUrl("streams.png").toString().replace("file://", "")));
            Qt.quit();
        })
    }
}
