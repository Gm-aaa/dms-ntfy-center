import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "ntfy-center"
    popoutWidth: 440
    popoutHeight: 560

    readonly property string helper: pluginService
        ? pluginService.getPluginPath("ntfyCenter") + "/scripts/ntfy_client.py"
        : ""
    readonly property string serverUrl: (pluginData.serverUrl || "https://ntfy.sh").trim()
    readonly property string topic: (pluginData.topic || "").trim()
    readonly property string accessToken: pluginData.accessToken || ""
    readonly property string username: pluginData.username || ""
    readonly property string password: pluginData.password || ""
    readonly property bool verifyTls: pluginData.verifyTls ?? true
    readonly property string publishTitle: (pluginData.publishTitle || "From Linux").trim()
    readonly property bool configured: helper !== "" && serverUrl !== "" && topic !== ""
    property string status: "connecting"
    property string errorText: ""
    property var messages: []
    property bool publishing: false
    property string resultText: ""
    signal publishSucceeded

    function refreshState() {
        if (!pluginService)
            return;
        status = pluginService.getGlobalVar("ntfyCenter", "status", "unconfigured");
        errorText = pluginService.getGlobalVar("ntfyCenter", "error", "");
        messages = pluginService.getGlobalVar("ntfyCenter", "messages", []);
    }

    function publish(text) {
        const clean = text.trim();
        if (!clean || publishing)
            return;
        if (!configured) {
            resultText = "Configure the ntfy server and topic first";
            resultTimer.restart();
            return;
        }
        publishing = true;
        resultText = "";
        const process = publishProcessComponent.createObject(root, {
            requestPayload: JSON.stringify({
                serverUrl: serverUrl,
                topic: topic,
                accessToken: accessToken,
                username: username,
                password: password,
                verifyTls: verifyTls,
                message: clean,
                title: publishTitle || "Custom message"
            })
        });
        process.running = true;
    }

    Connections {
        target: pluginService

        function onGlobalVarChanged(changedPluginId, varName) {
            if (changedPluginId === "ntfyCenter")
                root.refreshState();
        }
    }

    Component.onCompleted: refreshState()

    Component {
        id: publishProcessComponent

        Process {
            id: publishProcess

            property string requestPayload: ""
            property bool resultHandled: false

            command: ["python3", root.helper, "publish"]
            stdinEnabled: true

            stdout: StdioCollector {
                onStreamFinished: {
                    publishProcess.resultHandled = true;
                    root.publishing = false;
                    try {
                        const result = JSON.parse(text.trim());
                        if (result.kind === "published") {
                            root.resultText = "Sent";
                            root.publishSucceeded();
                        } else {
                            root.resultText = result.error || "Send failed";
                        }
                    } catch (error) {
                        root.resultText = "Failed to parse publish response";
                    }
                    resultTimer.restart();
                    publishProcess.destroy();
                }
            }

            onRunningChanged: {
                if (running)
                    write(requestPayload + "\n");
            }

            onExited: exitCode => {
                if (exitCode !== 0 && !resultHandled) {
                    Qt.callLater(function() {
                        if (!publishProcess.resultHandled) {
                            root.publishing = false;
                            root.resultText = "Send failed";
                            resultTimer.restart();
                            publishProcess.destroy();
                        }
                    });
                }
            }
        }
    }

    Timer {
        id: resultTimer
        interval: 2500
        onTriggered: root.resultText = ""
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.status === "online" ? "notifications_active" : "notifications_off"
                size: root.iconSize
                color: root.status === "online" ? Theme.primary : Theme.error
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.messages.length > 0 ? String(root.messages.length) : ""
                visible: text !== ""
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig ? root.barConfig.fontScale : undefined)
                color: Theme.widgetTextColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: root.status === "online" ? "notifications_active" : "notifications_off"
            size: root.iconSize
            color: root.status === "online" ? Theme.primary : Theme.error
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popoutRoot

            headerText: "ntfy Center"
            detailsText: {
                if (root.status === "unconfigured")
                    return "Not configured";
                if (root.status === "online")
                    return "Connected · " + root.topic;
                return "Disconnected" + (root.errorText ? " · " + root.errorText : "");
            }
            showCloseButton: true

            ColumnLayout {
                width: parent.width
                height: root.popoutHeight - popoutRoot.headerHeight - popoutRoot.detailsHeight
                spacing: Theme.spacingS

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.spacingS
                    Layout.rightMargin: Theme.spacingS

                    DankTextField {
                        id: messageInput

                        Layout.fillWidth: true
                        placeholderText: "Publish a message"
                        leftIconName: "edit"
                        showClearButton: true
                        enabled: !root.publishing && root.configured
                        onAccepted: root.publish(text)

                        Connections {
                            target: root

                            function onPublishSucceeded() {
                                messageInput.text = "";
                            }
                        }
                    }

                    DankButton {
                        text: root.publishing ? "Sending" : "Send"
                        iconName: "send"
                        enabled: !root.publishing && root.configured && messageInput.text.trim().length > 0
                        onClicked: root.publish(messageInput.text)
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.spacingM
                    text: root.resultText
                    visible: text !== ""
                    color: text === "Sent" ? Theme.primary : Theme.error
                    font.pixelSize: Theme.fontSizeSmall
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.spacingS
                    Layout.rightMargin: Theme.spacingS
                    height: 1
                    color: Theme.outlineVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.messages.length === 0
                    text: root.configured ? "No messages" : "Open plugin settings to configure ntfy"
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                ListView {
                    id: messageList

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: Theme.spacingS
                    Layout.rightMargin: Theme.spacingS
                    clip: true
                    spacing: Theme.spacingS
                    visible: root.messages.length > 0
                    model: root.messages

                    delegate: StyledRect {
                        required property var modelData

                        width: messageList.width
                        height: messageColumn.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        Column {
                            id: messageColumn

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingXS

                            Row {
                                width: parent.width
                                spacing: Theme.spacingS

                                StyledText {
                                    width: parent.width - timeText.width - parent.spacing
                                    text: modelData.title || "ntfy"
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    id: timeText

                                    text: new Date((modelData.time || 0) * 1000).toLocaleTimeString(Qt.locale(), "HH:mm")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }

                            StyledText {
                                width: parent.width
                                text: modelData.message || ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.Wrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Quickshell.execDetached(["dms", "cl", "copy", modelData.message || ""]);
                                ToastService.showInfo("Message copied");
                            }
                        }
                    }
                }
            }
        }
    }
}
