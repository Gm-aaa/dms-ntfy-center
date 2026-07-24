import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "ntfyCenter"
    property string tokenValue: ""
    property string passwordValue: ""
    property bool secretsLoaded: false

    function loadSecrets() {
        if (!pluginService)
            return;
        tokenValue = loadValue("accessToken", "");
        passwordValue = loadValue("password", "");
        secretsLoaded = true;
    }

    function saveSecret(key, value) {
        if (secretsLoaded)
            saveValue(key, value);
    }

    Component.onCompleted: Qt.callLater(loadSecrets)
    onPluginServiceChanged: Qt.callLater(loadSecrets)

    StyledText {
        width: parent.width
        text: "ntfy Center"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Connect any ntfy server to DankMaterialShell. Changes are applied automatically."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        text: "Connection"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
    }

    StringSetting {
        settingKey: "serverUrl"
        label: "Server URL"
        description: "Base URL of ntfy, without a trailing topic path."
        placeholder: "https://ntfy.sh"
        defaultValue: "https://ntfy.sh"
    }

    StringSetting {
        settingKey: "topic"
        label: "Topic"
        description: "Topic to subscribe to and publish messages on."
        placeholder: "my-topic"
        defaultValue: ""
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            text: "Access token"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "Recommended for authenticated servers. When set, username and password are ignored."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        DankTextField {
            width: parent.width
            text: root.tokenValue
            placeholderText: "tk_..."
            echoMode: TextInput.Password
            showPasswordToggle: true
            onTextEdited: root.tokenValue = text
            onEditingFinished: root.saveSecret("accessToken", text)
            onActiveFocusChanged: {
                if (!activeFocus)
                    root.saveSecret("accessToken", text);
            }
        }
    }

    StringSetting {
        settingKey: "username"
        label: "Username"
        description: "Optional HTTP Basic authentication username."
        placeholder: "username"
        defaultValue: ""
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            text: "Password"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "Optional HTTP Basic authentication password."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        DankTextField {
            width: parent.width
            text: root.passwordValue
            placeholderText: "password"
            echoMode: TextInput.Password
            showPasswordToggle: true
            onTextEdited: root.passwordValue = text
            onEditingFinished: root.saveSecret("password", text)
            onActiveFocusChanged: {
                if (!activeFocus)
                    root.saveSecret("password", text);
            }
        }
    }

    ToggleSetting {
        settingKey: "verifyTls"
        label: "Verify TLS certificates"
        description: "Keep this enabled unless the server intentionally uses a self-signed certificate."
        defaultValue: true
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
}
