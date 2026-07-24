# dms-ntfy-center

A DankMaterialShell composite plugin for receiving ntfy notifications, displaying
them in the DankBar, and publishing custom messages.

## Features

- Persistent ntfy JSON-stream subscription with automatic reconnect
- DMS desktop notifications and recent-message history
- Publish custom text from the DankBar popout
- Bearer token and HTTP Basic authentication
- Configurable server, topic, credentials, TLS verification, history, and title
- No external Python packages or manually edited configuration files

## Requirements

- DankMaterialShell 1.5.0 or newer
- Python 3.10 or newer

## Install

Clone or copy this repository to the DMS plugin directory:

```bash
git clone <repository-url> \
  ~/.config/DankMaterialShell/plugins/ntfyCenter
```

Open DMS Settings → Plugins, scan for plugins, and enable **ntfy Center**. Add
`ntfyCenter` to the DankBar layout if it is not already present.

Open the plugin settings and enter the ntfy server URL and topic. For protected
topics, enter either an access token or a username and password. An access token
takes precedence.

All options are stored by DMS in its namespaced plugin settings. The access token
and password are hidden in the UI, but DMS settings are not an encrypted secret
store; protect your user configuration directory accordingly.

## Development

For a live development checkout, link the repository into the plugin directory:

```bash
ln -s "$PWD" ~/.config/DankMaterialShell/plugins/ntfyCenter
dms ipc call plugins reload ntfyCenter
```

Validate QML files with:

```bash
qmllint -I /usr/share/quickshell/dms \
  NtfyDaemon.qml NtfyWidget.qml NtfySettings.qml
```

## License

MIT
