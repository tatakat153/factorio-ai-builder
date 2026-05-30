# Factorio AI Builder — Factorio 侧部署

## 前提

- Factorio 2.0+
- 游戏必须以 **Multiplayer → Host saved game** 方式启动（即使是单人）
- 这是 RCON 功能的前提条件

## 步骤

### 1. 安装 Mod

将 `factorio-ai-builder/` 整个目录复制到 Factorio 的 mods 目录：

**Windows**: `%APPDATA%\Factorio\mods\factorio-ai-builder\`
**Linux**: `~/.factorio/mods/factorio-ai-builder/`
**macOS**: `~/Library/Application Support/factorio/mods/factorio-ai-builder/`

### 2. 启用 RCON

在 Factorio 配置文件末尾添加两行：

**Windows**: 编辑 `%APPDATA%\Factorio\config\config.ini`
**Linux**: 编辑 `~/.factorio/config/config.ini`

```ini
local-rcon-socket=0.0.0.0:34198
local-rcon-password=factorio
```

> ⚠️ 如果 Factorio 和桥接服务在不同机器上，把 `0.0.0.0` 保持为 `0.0.0.0`（监听所有网络接口）。如果在同一台机器，可用 `127.0.0.1`。

### 3. 启动游戏

- 打开 Factorio
- 主菜单 → Multiplayer → Host saved game
- 选择存档，确保 "Verify user identity" 可以关闭
- 启动

### 4. 验证

加载游戏后，按 `~` 打开控制台，输入：

```
/ai-status
```

如果看到 "No agent exists"，说明 mod 加载成功。

然后输入：

```
/ai-templates
```

应列出所有可用的建造模板。

## 游戏内命令

| 命令 | 说明 |
|------|------|
| `/ai-status` | 查看 AI 角色状态 |
| `/ai-templates` | 列出可用建造模板 |
| `/ai-stop` | 紧急停止 |
| `/ai-reset` | 急停复位 |
| `/ai-mark [label]` | 标记当前光标附近的区域 |
