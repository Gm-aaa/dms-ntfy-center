# Changelog

本项目的主要变更都会记录在此文件中。版本格式遵循
[Semantic Versioning](https://semver.org/)。

## [1.1.0] - 2026-07-24

### Added

- ntfy JSON 流后台订阅与自动重连。
- DMS 桌面通知和 DankBar 消息历史面板。
- 从 DankBar 发布自定义文本。
- Access Token 和 HTTP Basic 认证。
- TLS 证书验证开关。
- 可配置的历史数量、历史时间范围和默认发布标题。
- DMS 原生插件设置界面。
- 随插件发布的零第三方依赖 Python helper。

### Changed

- 将服务器、主题和认证信息迁移到 DMS 插件设置命名空间。
- 去除对外部 `~/.config/ntfy-dms/config.json` 的依赖。
- 去除对外部 `~/.local/bin/ntfy-dms` helper 的依赖。
- 按服务器和主题隔离重连消息游标。

### Fixed

- 修复消息实际发布成功但界面显示发送失败的问题。
- 修复历史加载与实时消息同时发生时可能覆盖新消息的问题。
