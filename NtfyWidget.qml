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
    readonly property string publishTitle: (pluginData.publishTitle || "From Linux").trim()
    readonly property var subscriptions: normalizeSubscriptions(pluginData)
    readonly property var publishTargets: enabledSubscriptions(pluginData)
    readonly property bool configured: helper !== "" && publishTargets.length > 0

    property string selectedSubId: ""
    readonly property var selectedSub: {
        if (publishTargets.length === 0)
            return null;
        for (let i = 0; i < publishTargets.length; i++) {
            if (publishTargets[i].id === selectedSubId)
                return publishTargets[i];
        }
        return publishTargets[0];
    }

    property string status: "connecting"
    property string errorText: ""
    property var messages: []
    property bool publishing: false
    property string resultText: ""
    signal publishSucceeded

    // --- shared subscription helpers (inlined; relative .js imports break
    // --- when Quickshell hot-reloads a component with a ?t= cache-buster) ---

    function normalizeSubscription(raw) {
        const s = (raw && typeof raw === "object") ? raw : {};
        let serverUrl = String(s.serverUrl || "https://ntfy.sh").trim();
        if (!serverUrl)
            serverUrl = "https://ntfy.sh";
        return {
            id: s.id ? String(s.id) : (serverUrl + "|" + String(s.topic || "").trim()),
            name: s.name ? String(s.name) : "",
            enabled: s.enabled !== false,
            serverUrl: serverUrl,
            topic: String(s.topic || "").trim(),
            accessToken: s.accessToken ? String(s.accessToken) : "",
            username: s.username ? String(s.username) : "",
            password: s.password ? String(s.password) : "",
            verifyTls: s.verifyTls !== false
        };
    }

    function normalizeSubscriptions(data) {
        const source = data || {};
        if (source.subscriptions !== undefined && Array.isArray(source.subscriptions)) {
            const out = [];
            for (let i = 0; i < source.subscriptions.length; i++)
                out.push(normalizeSubscription(source.subscriptions[i]));
            return out;
        }

        const legacyTopic = String(source.topic || "").trim();
        if (legacyTopic.length === 0)
            return [];
        return [normalizeSubscription({
            id: "legacy",
            name: legacyTopic,
            enabled: true,
            serverUrl: source.serverUrl || "https://ntfy.sh",
            topic: legacyTopic,
            accessToken: source.accessToken || "",
            username: source.username || "",
            password: source.password || "",
            verifyTls: source.verifyTls !== false
        })];
    }

    function enabledSubscriptions(data) {
        const all = normalizeSubscriptions(data);
        const out = [];
        for (let i = 0; i < all.length; i++) {
            if (all[i].enabled !== false)
                out.push(all[i]);
        }
        return out;
    }

    function subscriptionLabel(sub) {
        if (!sub)
            return "ntfy";
        if (sub.name)
            return sub.name;
        if (sub.topic)
            return sub.topic;
        return "ntfy";
    }

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
        if (!configured || !selectedSub) {
            resultText = "Configure a subscription first";
            resultTimer.restart();
            return;
        }
        publishing = true;
        resultText = "";
        const process = publishProcessComponent.createObject(root, {
            requestPayload: JSON.stringify({
                serverUrl: selectedSub.serverUrl,
                topic: selectedSub.topic,
                accessToken: selectedSub.accessToken || "",
                username: selectedSub.username || "",
                password: selectedSub.password || "",
                verifyTls: selectedSub.verifyTls !== false,
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
                if (root.status === "online") {
                    const count = root.publishTargets.length;
                    return "Connected · " + count + (count === 1 ? " subscription" : " subscriptions");
                }
                return "Disconnected" + (root.errorText ? " · " + root.errorText : "");
            }
            showCloseButton: true

            ColumnLayout {
                width: parent.width
                height: root.popoutHeight - popoutRoot.headerHeight - popoutRoot.detailsHeight
                spacing: Theme.spacingS

                DankDropdown {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.spacingS
                    Layout.rightMargin: Theme.spacingS
                    visible: root.publishTargets.length > 1
                    text: "Publish to"
                    description: ""
                    currentValue: root.selectedSub ? root.subscriptionLabel(root.selectedSub) : ""
                    options: root.publishTargets.map(function(sub) {
                        return root.subscriptionLabel(sub);
                    })
                    onValueChanged: value => {
                        for (let i = 0; i < root.publishTargets.length; i++) {
                            const candidate = root.publishTargets[i];
                            if (root.subscriptionLabel(candidate) === value) {
                                root.selectedSubId = candidate.id;
                                break;
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.spacingS
                    Layout.rightMargin: Theme.spacingS

                    DankTextField {
                        id: messageInput

                        Layout.fillWidth: true
                        placeholderText: root.selectedSub ? "Publish to " + root.subscriptionLabel(root.selectedSub) : "Publish a message"
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
                        id: messageDelegate

                        required property var modelData
                        readonly property string verificationCode: modelData.verification_code || ""
                        readonly property string sourceLabel: modelData._subName || modelData.topic || ""

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
                                visible: messageDelegate.sourceLabel !== ""
                                text: messageDelegate.sourceLabel
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.primary
                                elide: Text.ElideRight
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

                            StyledText {
                                width: parent.width
                                visible: messageDelegate.verificationCode !== ""
                                text: "Verification code: " + messageDelegate.verificationCode + " · Click to copy"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.DemiBold
                                color: Theme.primary
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const copyText = messageDelegate.verificationCode || modelData.message || "";
                                Quickshell.execDetached(["dms", "cl", "copy", copyText]);
                                ToastService.showInfo(messageDelegate.verificationCode
                                    ? "Verification code copied"
                                    : "Message copied");
                            }
                        }
                    }
                }
            }
        }
    }
}