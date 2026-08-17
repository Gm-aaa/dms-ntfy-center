import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property string helper: pluginService
        ? pluginService.getPluginPath("ntfyCenter") + "/scripts/ntfy_client.py"
        : ""
    readonly property string serverUrl: (pluginData.serverUrl || "https://ntfy.sh").trim()
    readonly property string topic: (pluginData.topic || "").trim()
    readonly property string accessToken: pluginData.accessToken || ""
    readonly property string username: pluginData.username || ""
    readonly property string password: pluginData.password || ""
    readonly property bool verifyTls: pluginData.verifyTls ?? true
    readonly property bool showNotifications: pluginData.showNotifications ?? true
    readonly property int historyLimit: pluginData.historyLimit ?? 20
    readonly property int historyHours: pluginData.historyHours ?? 24
    readonly property bool configured: helper !== "" && serverUrl !== "" && topic !== ""
    property var messages: []
    property bool reconfiguring: false

    function clientPayload() {
        return {
            serverUrl: serverUrl,
            topic: topic,
            accessToken: accessToken,
            username: username,
            password: password,
            verifyTls: verifyTls,
            historyLimit: historyLimit,
            historyHours: historyHours
        };
    }

    function updateGlobalState(name, value) {
        if (pluginService)
            pluginService.setGlobalVar("ntfyCenter", name, value);
    }

    function ensureBarWidget() {
        // 只保证 widget 存在即可，不再强制塞进 rightWidgets（右上角）。
        // 优先以 centerWidgets 为准；若用户从两处都移除则补回 centerWidgets。
        const bar = SettingsData.barConfigs[0];
        if (!bar)
            return;
        const inCenter = (bar.centerWidgets || []).some(item => (typeof item === "string" ? item : item.id) === "ntfyCenter");
        const inRight = (bar.rightWidgets || []).some(item => (typeof item === "string" ? item : item.id) === "ntfyCenter");
        if (inCenter || inRight)
            return;
        SettingsData.updateBarConfig(bar.id, {
            centerWidgets: (bar.centerWidgets || []).concat([{id: "ntfyCenter", enabled: true}])
        });
    }

    function mergeMessage(message, notify) {
        if (!message || !message.id)
            return;
        const duplicate = messages.some(item => item.id === message.id);
        if (!duplicate) {
            const next = [message].concat(messages).slice(0, historyLimit);
            messages = next;
            updateGlobalState("messages", next);
            updateGlobalState("lastMessage", message);
        }
        if (notify && !duplicate && showNotifications)
            showSystemNotification(message);
    }

    function showSystemNotification(message) {
        const process = notificationProcessComponent.createObject(root, {
            notificationTitle: message.title || "ntfy",
            notificationBody: message.message || ""
        });
        process.running = true;
    }

    function handleWatchLine(line) {
        const text = line.trim();
        if (!text)
            return;
        try {
            const event = JSON.parse(text);
            if (event.kind === "status") {
                updateGlobalState("status", event.state || "offline");
                updateGlobalState("error", event.error || "");
            } else if (event.kind === "message") {
                mergeMessage(event.data, true);
            } else if (event.kind === "error") {
                updateGlobalState("status", "offline");
                updateGlobalState("error", event.error || "ntfy client failed");
            }
        } catch (error) {
            updateGlobalState("status", "offline");
            updateGlobalState("error", "Failed to parse ntfy response");
        }
    }

    function applyConfiguration() {
        reconfiguring = true;
        restartTimer.stop();
        historyProcess.running = false;
        watchProcess.running = false;
        messages = [];
        updateGlobalState("messages", []);
        updateGlobalState("error", "");
        if (!configured) {
            updateGlobalState("status", "unconfigured");
            reconfiguring = false;
            return;
        }
        updateGlobalState("status", "connecting");
        Qt.callLater(function() {
            reconfiguring = false;
            historyProcess.running = true;
            watchProcess.running = true;
        });
    }

    onPluginDataChanged: configurationTimer.restart()

    Component {
        id: notificationProcessComponent

        Process {
            property string notificationTitle: ""
            property string notificationBody: ""

            command: [
                "dms",
                "notify",
                notificationTitle,
                notificationBody,
                "--app",
                "ntfy",
                "--icon",
                "notifications_active",
                "--timeout",
                "8000"
            ]

            onExited: exitCode => {
                if (exitCode !== 0) {
                    Quickshell.execDetached([
                        "notify-send",
                        "--app-name=ntfy",
                        "--icon=notifications-active",
                        "--expire-time=8000",
                        notificationTitle,
                        notificationBody
                    ]);
                }
                destroy();
            }
        }
    }

    Process {
        id: historyProcess
        command: ["python3", root.helper, "history"]
        stdinEnabled: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text.trim());
                    if (result.kind === "history") {
                        const combined = result.data.concat(root.messages);
                        const seen = {};
                        root.messages = combined.filter(function(message) {
                            if (!message.id || seen[message.id])
                                return false;
                            seen[message.id] = true;
                            return true;
                        }).sort(function(left, right) {
                            return (right.time || 0) - (left.time || 0);
                        }).slice(0, root.historyLimit);
                        root.updateGlobalState("messages", root.messages);
                        if (root.messages.length > 0)
                            root.updateGlobalState("lastMessage", root.messages[0]);
                    } else if (result.kind === "error") {
                        root.updateGlobalState("error", result.error || "Failed to load history");
                    }
                } catch (error) {
                    root.updateGlobalState("error", "Failed to load message history");
                }
            }
        }

        onRunningChanged: {
            if (running)
                write(JSON.stringify(root.clientPayload()) + "\n");
        }
    }

    Process {
        id: watchProcess
        command: ["python3", root.helper, "watch"]
        stdinEnabled: true

        stdout: SplitParser {
            onRead: line => root.handleWatchLine(line)
        }

        onRunningChanged: {
            if (running) {
                write(JSON.stringify(root.clientPayload()) + "\n");
            } else if (!root.reconfiguring && root.configured) {
                restartTimer.restart();
            }
        }
    }

    Timer {
        id: configurationTimer
        interval: 350
        repeat: false
        onTriggered: root.applyConfiguration()
    }

    Timer {
        id: restartTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (!watchProcess.running && root.configured)
                watchProcess.running = true;
        }
    }

    IpcHandler {
        target: "ntfyCenter"

        function status(): string {
            return JSON.stringify({
                state: pluginService ? pluginService.getGlobalVar("ntfyCenter", "status", "unknown") : "unknown",
                server: root.serverUrl,
                topic: root.topic,
                messageCount: root.messages.length,
                lastMessageId: root.messages.length > 0 ? root.messages[0].id : ""
            });
        }
    }

    Component.onCompleted: {
        ensureBarWidget();
        updateGlobalState("messages", []);
        applyConfiguration();
    }

    Component.onDestruction: {
        reconfiguring = true;
        watchProcess.running = false;
        historyProcess.running = false;
        restartTimer.stop();
        configurationTimer.stop();
    }
}
