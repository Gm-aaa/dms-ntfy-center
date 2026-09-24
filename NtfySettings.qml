import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "ntfyCenter"

    property var subs: []
    property bool loading: true

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

    function blankSubscription() {
        return normalizeSubscription({
            id: newSubId(),
            name: "",
            enabled: true,
            serverUrl: "https://ntfy.sh",
            topic: ""
        });
    }

    function loadSubs() {
        loading = true;
        const rawSubs = loadValue("subscriptions", undefined);
        if (rawSubs !== undefined && rawSubs !== null) {
            subs = normalizeSubscriptions({
                subscriptions: rawSubs
            });
        } else {
            // Migrate the pre-1.3.0 single server/topic settings.
            const migrated = normalizeSubscriptions({
                serverUrl: loadValue("serverUrl", "https://ntfy.sh"),
                topic: loadValue("topic", ""),
                accessToken: loadValue("accessToken", ""),
                username: loadValue("username", ""),
                password: loadValue("password", ""),
                verifyTls: loadValue("verifyTls", true)
            });
            subs = migrated;
            if (migrated.length > 0)
                saveValue("subscriptions", migrated);
        }
        loading = false;
    }

    function persist() {
        saveValue("subscriptions", subs);
    }

    function addSub() {
        subs = subs.concat([blankSubscription()]);
        persist();
    }

    function removeSub(index) {
        const next = subs.slice();
        next.splice(index, 1);
        subs = next;
        persist();
    }

    // Field edits mutate in place and persist, without reassigning `subs`.
    // Reassigning would rebuild the Repeater and steal focus from the field
    // the user is typing in.
    function updateField(index, key, value) {
        if (index < 0 || index >= subs.length)
            return;
        subs[index][key] = value;
        persist();
    }

    Component.onCompleted: Qt.callLater(loadSubs)
    onPluginServiceChanged: Qt.callLater(loadSubs)

    StyledText {
        width: parent.width
        text: "ntfy Center"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Connect one or more ntfy servers and topics to DankMaterialShell. Changes are applied automatically."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        text: "Subscriptions"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Each subscription watches one topic. Disabled subscriptions stay saved but are not connected."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: root.subs
        delegate: subCardComponent
    }

    StyledText {
        width: parent.width
        visible: root.subs.length === 0
        text: "No subscriptions yet. Add one to start receiving notifications."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    DankButton {
        text: "Add subscription"
        iconName: "add"
        onClicked: root.addSub()
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineVariant
    }

    StyledText {
        width: parent.width
        text: "Behavior"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "showNotifications"
        label: "Show desktop notifications"
        description: "Add incoming messages to the DMS notification center and show a popup."
        defaultValue: true
    }

    SliderSetting {
        settingKey: "historyLimit"
        label: "Message history limit"
        description: "Maximum number of recent messages shown in the popout."
        defaultValue: 20
        minimum: 5
        maximum: 50
        unit: ""
    }

    SliderSetting {
        settingKey: "historyHours"
        label: "History window"
        description: "How far back to load messages when the plugin starts."
        defaultValue: 24
        minimum: 1
        maximum: 168
        unit: "h"
    }

    StringSetting {
        settingKey: "publishTitle"
        label: "Default publish title"
        description: "Title used for custom messages sent from this desktop."
        placeholder: "From Linux"
        defaultValue: "From Linux"
    }

    Component {
        id: subCardComponent

        Rectangle {
            id: card

            required property var modelData
            required property int index

            property bool enabledState: modelData.enabled !== false
            property bool tlsState: modelData.verifyTls !== false

            width: parent.width
            height: cardColumn.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
            border.width: 1
            border.color: Theme.outlineVariant

            Column {
                id: cardColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        width: parent.width - enabledToggle.width - removeButton.width - parent.spacing * 2
                        text: card.modelData.name || (card.modelData.topic || "") || ("Subscription " + (card.index + 1))
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DankToggle {
                        id: enabledToggle

                        text: ""
                        hideText: true
                        checked: card.enabledState
                        anchors.verticalCenter: parent.verticalCenter
                        onToggled: value => {
                            card.enabledState = value;
                            root.updateField(card.index, "enabled", value);
                        }
                    }

                    DankButton {
                        id: removeButton

                        text: ""
                        iconName: "delete"
                        width: 44
                        horizontalPadding: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: root.removeSub(card.index)
                    }
                }

                StyledText {
                    text: "Name (optional)"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                DankTextField {
                    width: parent.width
                    placeholderText: "AMSAT SSTV"
                    text: card.modelData.name
                    onEditingFinished: root.updateField(card.index, "name", text)
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            root.updateField(card.index, "name", text);
                    }
                }

                StyledText {
                    text: "Server URL"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                DankTextField {
                    width: parent.width
                    placeholderText: "https://ntfy.sh"
                    text: card.modelData.serverUrl
                    onEditingFinished: root.updateField(card.index, "serverUrl", text)
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            root.updateField(card.index, "serverUrl", text);
                    }
                }

                StyledText {
                    text: "Topic"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                DankTextField {
                    width: parent.width
                    placeholderText: "my-topic"
                    text: card.modelData.topic
                    onEditingFinished: root.updateField(card.index, "topic", text)
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            root.updateField(card.index, "topic", text);
                    }
                }

                StyledText {
                    text: "Access token (optional, preferred over username/password)"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    wrapMode: Text.WordWrap
                    width: parent.width
                }

                DankTextField {
                    width: parent.width
                    placeholderText: "tk_..."
                    text: card.modelData.accessToken
                    echoMode: TextInput.Password
                    showPasswordToggle: true
                    onEditingFinished: root.updateField(card.index, "accessToken", text)
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            root.updateField(card.index, "accessToken", text);
                    }
                }

                StyledText {
                    text: "Username (optional, HTTP Basic)"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                DankTextField {
                    width: parent.width
                    placeholderText: "username"
                    text: card.modelData.username
                    onEditingFinished: root.updateField(card.index, "username", text)
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            root.updateField(card.index, "username", text);
                    }
                }

                StyledText {
                    text: "Password (optional, HTTP Basic)"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                DankTextField {
                    width: parent.width
                    placeholderText: "password"
                    text: card.modelData.password
                    echoMode: TextInput.Password
                    showPasswordToggle: true
                    onEditingFinished: root.updateField(card.index, "password", text)
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            root.updateField(card.index, "password", text);
                    }
                }

                DankToggle {
                    width: parent.width
                    text: "Verify TLS certificates"
                    description: "Disable only for self-signed servers."
                    checked: card.tlsState
                    onToggled: value => {
                        card.tlsState = value;
                        root.updateField(card.index, "verifyTls", value);
                    }
                }
            }
        }
    }
}