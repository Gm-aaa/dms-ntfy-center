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
    readonly property bool showNotifications: pluginData.showNotifications ?? true
    readonly property int historyLimit: pluginData.historyLimit ?? 20
    readonly property int historyHours: pluginData.historyHours ?? 24

    // Normalized subscription list. Kept separate from `pluginData` so that
    // unrelated setting changes (for example toggling desktop notifications)
    // do not tear down and restart every watcher.
    property var subList: []
    property var messages: []
    property var subStates: ({})
    property bool reconfiguring: false

    readonly property var activeSubscriptions: {
        var out = [];
        for (var i = 0; i < subList.length; i++) {
            if (subList[i].enabled !== false)
                out.push(subList[i]);
        }
        return out;
    }
    readonly property bool configured: helper !== "" && activeSubscriptions.length > 0

    readonly property int onlineCount: {
        var n = 0;
        for (var key in subStates) {
            if (subStates[key] && subStates[key].state === "online")
                n++;
        }
        return n;
    }

    readonly property string status: {
        if (!configured)
            return "unconfigured";
        if (onlineCount > 0)
            return "online";
        return "connecting";
    }

    readonly property string errorText: {
        for (var key in subStates) {
            if (subStates[key] && subStates[key].error)
                return subStates[key].error;
        }
        return "";
    }

    // --- shared subscription helpers (inlined; relative .js imports break
    // --- when Quickshell hot-reloads a component with a ?t= cache-buster) ---

    function newSubId() {
        return "sub_" + Date.now().toString(36) + "_" + Math.random().toString(36).slice(2, 8);
    }

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

    // If `subscriptions` is present it is always honoured, even when empty, so
    // a user who removed every subscription does not get the legacy fields
    // resurrected. When absent, pre-1.3.0 single server/topic settings are
    // migrated into a one-element list.
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

    function subKeyOf(sub) {
        const server = String(sub && sub.serverUrl || "").trim();
        const topic = String(sub && sub.topic || "").trim();
        return server + "|" + topic;
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

    function refreshSubscriptions() {
        const next = normalizeSubscriptions(root.pluginData);
        if (JSON.stringify(next) === JSON.stringify(root.subList))
            return;
        root.subList = next;

        // Drop state for subscriptions that no longer exist.
        const valid = {};
        for (let i = 0; i < next.length; i++)
            valid[subKeyOf(next[i])] = true;
        const pruned = {};
        for (const key in root.subStates) {
            if (valid[key])
                pruned[key] = root.subStates[key];
        }
        root.subStates = pruned;
    }

    function setSubStatus(key, state, error) {
        const next = Object.assign({}, root.subStates);
        next[key] = {
            state: state || "offline",
            error: error || ""
        };
        root.subStates = next;
    }

    function updateGlobalState(name, value) {
        if (pluginService)
            pluginService.setGlobalVar("ntfyCenter", name, value);
    }

    function tagMessage(message, sub) {
        const copy = Object.assign({}, message);
        const server = (sub.serverUrl || "").trim();
        const topic = (sub.topic || "").trim();
        copy._serverUrl = server;
        copy._topic = topic;
        copy._subName = subscriptionLabel(sub);
        copy._key = server + "|" + topic + "|" + (message.id || "");
        return copy;
    }

    function mergeMessage(message, notify) {
        if (!message || !message.id || !message._key)
            return;
        if (root.messages.some(function(item) {
            return item._key === message._key;
        }))
            return;
        const next = [message].concat(root.messages).slice(0, historyLimit);
        root.messages = next;
        root.updateGlobalState("messages", next);
        root.updateGlobalState("lastMessage", next[0]);
        if (notify && showNotifications)
            root.showSystemNotification(message);
    }

    function mergeHistory(list) {
        if (!list || list.length === 0)
            return;
        const seen = {};
        for (let i = 0; i < root.messages.length; i++) {
            if (root.messages[i]._key)
                seen[root.messages[i]._key] = true;
        }
        let next = root.messages.slice();
        let added = false;
        for (let i = 0; i < list.length; i++) {
            const message = list[i];
            if (!message || !message._key || seen[message._key])
                continue;
            seen[message._key] = true;
            next.push(message);
            added = true;
        }
        if (!added)
            return;
        next.sort(function(left, right) {
            return (right.time || 0) - (left.time || 0);
        });
        next = next.slice(0, historyLimit);
        root.messages = next;
        root.updateGlobalState("messages", next);
        if (next.length > 0)
            root.updateGlobalState("lastMessage", next[0]);
    }

    function showSystemNotification(message) {
        const process = notificationProcessComponent.createObject(root, {
            notificationTitle: message.title || "ntfy",
            notificationBody: message.message || ""
        });
        process.running = true;
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

    onStatusChanged: updateGlobalState("status", status)
    onErrorTextChanged: updateGlobalState("error", errorText)

    onPluginDataChanged: {
        refreshSubscriptions();
    }

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

    // One watcher per enabled subscription. Each watcher owns a live JSON
    // stream plus a one-shot history loader. Messages are tagged with their
    // source so dedup keys stay unique across servers with identical topics.
    Repeater {
        model: root.activeSubscriptions

        Item {
            id: watcher

            required property var modelData

            readonly property var sub: modelData
            readonly property string key: root.subKeyOf(sub)
            property bool dying: false

            function payload(extra) {
                const base = {
                    serverUrl: sub.serverUrl,
                    topic: sub.topic,
                    accessToken: sub.accessToken || "",
                    username: sub.username || "",
                    password: sub.password || "",
                    verifyTls: sub.verifyTls !== false,
                    historyLimit: root.historyLimit,
                    historyHours: root.historyHours
                };
                return Object.assign(base, extra || {});
            }

            function handleLine(line) {
                const text = line.trim();
                if (!text)
                    return;
                try {
                    const event = JSON.parse(text);
                    if (event.kind === "status") {
                        root.setSubStatus(key, event.state || "offline", event.error || "");
                    } else if (event.kind === "message") {
                        root.mergeMessage(root.tagMessage(event.data, sub), true);
                    } else if (event.kind === "error") {
                        root.setSubStatus(key, "offline", event.error || "ntfy client failed");
                    }
                } catch (error) {
                    root.setSubStatus(key, "offline", "Failed to parse ntfy response");
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
                                const tagged = result.data.map(function(message) {
                                    return root.tagMessage(message, watcher.sub);
                                });
                                root.mergeHistory(tagged);
                            }
                        } catch (error) {
                            // History is best-effort; the live stream still works.
                        }
                    }
                }

                onRunningChanged: {
                    if (running)
                        write(JSON.stringify(watcher.payload()) + "\n");
                }
            }

            Process {
                id: watchProcess

                command: ["python3", root.helper, "watch"]
                stdinEnabled: true

                stdout: SplitParser {
                    onRead: line => watcher.handleLine(line)
                }

                onRunningChanged: {
                    if (running) {
                        write(JSON.stringify(watcher.payload()) + "\n");
                    } else if (!watcher.dying && root.configured) {
                        watcher.restartTimer.restart();
                    }
                }
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

            Component.onCompleted: {
                root.setSubStatus(key, "connecting", "");
                historyProcess.running = true;
                watchProcess.running = true;
            }

            Component.onDestruction: {
                dying = true;
                restartTimer.stop();
                watchProcess.running = false;
                historyProcess.running = false;
            }
        }
    }

    IpcHandler {
        target: "ntfyCenter"

        function status(): string {
            const subs = root.activeSubscriptions.map(function(sub) {
                const state = root.subStates[root.subKeyOf(sub)] || {};
                return {
                    name: root.subscriptionLabel(sub),
                    serverUrl: sub.serverUrl,
                    topic: sub.topic,
                    state: state.state || "connecting",
                    error: state.error || ""
                };
            });
            return JSON.stringify({
                state: root.status,
                subscriptions: subs,
                messageCount: root.messages.length,
                lastMessageId: root.messages.length > 0 ? root.messages[0].id : ""
            });
        }
    }

    Component.onCompleted: {
        ensureBarWidget();
        loadPluginData();
        refreshSubscriptions();
        updateGlobalState("messages", []);
        updateGlobalState("status", status);
        updateGlobalState("error", errorText);
    }

    Component.onDestruction: {
        reconfiguring = true;
    }
}