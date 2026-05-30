# Factorio AI Builder

AI 控制的 Factorio 建造助手。支持稀疏地图感知、模板批量建造、区域标记、紧急停止。

**版本**: 0.2.0-beta

该版本挖掘放置时会出现bug,因作者马上高考，故近日不会更新。

该版本目前只支持HanaAgent,以后考虑兼容OpenClaw等。

## 使用方法

### 启动顺序

```
1. Steam 启动 Factorio → Multiplayer → Host saved game → 加载存档
2. 终端运行: cd bridge && python main.py
3. 重启 HanaAgent（加载插件）
```

桥接启动后自动连接 RCON，终端看到 `Connected to Factorio RCON` 即成功。

### 游戏内操作

按 `~` 打开控制台，输入以下命令直接控制 Mod：

```
/ai-status         查看 AI 角色位置、血量、背包、当前动作
/ai-templates      列出 8 个可用建造模板
/ai-stop           紧急停止（取消所有操作）
/ai-reset          急停复位
/ai-mark 铁矿区     标记当前光标附近区域，供 AI 查询详情
```

### HanaAgent 对话

在 HanaAgent 对话框用自然语言指挥建造：

```
"帮我查一下 Factorio 里 AI 助手的状态"
"在我旁边的铁矿附近建一排电炉烧铁板"
"走到 (-200, -145) 挖 50 个铁矿"
"看看我基地周围的布局，分析哪里可以优化"
```

AI 会自动调用对应工具完成操作。工具分为两个 Profile：

**Planner（规划角色，13 工具）**：
- `factorio_get_overview` — 查看区域摘要（chunk 级稀疏数据）
- `factorio_mark_area` / `factorio_get_area_detail` — 圈地查询详情
- `factorio_unmark_area` — 删除标记（主动清理缓存）
- `factorio_get_recipes` / `factorio_get_technologies` — 查配方和科技
- `factorio_get_inventory` / `factorio_get_agent_state` — 查背包和状态
- `factorio_start_research` / `factorio_craft` — 开始研究和手搓
- `factorio_list_templates` / `factorio_list_marks` — 查看模板和标记

**Executor（执行角色，14 工具）**：
- `factorio_walk_to` — 走到精确坐标
- `factorio_approach_to` — 走到目标附近（采矿/建造前使用，避免走进障碍物）
- `factorio_mine` — 挖掘资源
- `factorio_place_entity` / `factorio_pickup_entity` — 放置/拆除建筑
- `factorio_set_recipe` / `factorio_insert_items` / `factorio_extract_items` — 配置机器
- `factorio_build_batch` — 模板批量建造（一键放 8 个熔炉+配套）
- `factorio_check_batch` / `factorio_resume_batch` / `factorio_cancel_batch` — 管理批量进度
- `factorio_emergency_stop` / `factorio_connect` — 急停和连接

### 建造模板使用

批量建造用 `factorio_build_batch`，一次调用完成整套设施铺设：

```
"在 (100, 200) 建 8 个电炉烧铁板"
→ factorio_build_batch("smelter_row", anchor=(100,200), count=8, recipe="iron-plate")
→ 自动铺设: 8×电炉 + 16×传送带 + 16×爪子 + 8×电线杆
→ 每 tick 放 3 个实体（可在 Mod 设置调整速度）
→ 遇到障碍暂停，汇报给 AI 决策（跳过/拆除/改布局）
```

可用模板：`smelter_row`, `stone_furnace_row`, `assembler_grid`, `miner_array`, `steam_power_unit`, `belt_bus`, `lab_cluster`, `wall_segment`

### 区域查询

两阶段感知，避免 token 浪费：

```
# 阶段1: 概览（chunk 级摘要，数据量小）
factorio_get_overview(center_x=0, center_y=0, radius_chunks=3)
→ chunk(-2,-1): 铁矿(较多 ~98K), 石炉×4, 传送带×~30

# 阶段2: 圈地详情（实体压缩，精确但可控）
factorio_mark_area("iron_zone", 60,60, 100,100, "铁矿区")
factorio_get_area_detail("iron_zone")
→ 8 个相同配方电炉合并为 1 条, 32 节传送带折叠为路径段
→ 347 个实体压缩成 28 条摘要

# AI 负责清理不需要的标记
factorio_unmark_area("old_zone")
```

### 成本优化：双角色分离

可选但推荐——用不同模型做规划和执行：

```
# 在 HanaAgent 中：
subagent(name="ming", task="查看 iron_zone, 规划 8 个电炉的建造方案")
  → Planner profile, 用强推理模型（约 3K tokens）

subagent(name="janitor", task="按方案执行建造，遇到障碍汇报")
  → Executor profile, 用便宜模型（约 9K tokens）
```

比单一模型节省约 60% 推理成本。详见 [ARCHITECTURE.md](ARCHITECTURE.md)。

### 常见问题

**Q: 助手不动 / 卡住了？**
A: 按 `~` 输入 `/ai-stop` 再 `/ai-reset`，然后重新发 walk 指令。如果目标在障碍物里，用 `approach_to` 代替 `walk_to`。

**Q: 挖掘/放置报错？**
A: 确保桥接服务正常运行，RCON 连接状态为 `connected: true`。检查 Factorio 是否以 Multiplayer 模式启动。

**Q: 背包是空的但 craft 失败？**
A: 助手初始背包为空。先用 `factorio_mine` 挖矿获取原料，或用手动方式给助手物品。

**Q: 批量建造暂停了？**
A: 用 `factorio_check_batch(batch_id)` 查看原因（障碍/缺料），AI 决定后用 `factorio_resume_batch(batch_id, "skip_obstacles")` 继续。

---

## 架构

```
HanaAgent 插件 (25 工具, 双 profile)
    ↕ HTTP
Python 桥接服务 (FastAPI)
    ↕ RCON
Factorio Mod (Lua, 单位寻路 + 角色物品栏)
```

## 快速开始

### 1. Factorio Mod

将 `mod/factorio-ai-builder/` 复制到 Factorio 的 `mods/` 目录。

在 `config.ini` 中启用 RCON：
```ini
local-rcon-socket=127.0.0.1:34198
local-rcon-password=factorio
```

以 **Multiplayer → Host saved game** 启动游戏。

### 2. 桥接服务

```bash
cd bridge
pip install factorio-rcon-py fastapi uvicorn pydantic
python main.py
```

编辑 `bridge/config.ini` 修改 RCON 连接参数。

### 3. HanaAgent 插件

将 `plugins/ai-builder-hana/` 复制到 HanaAgent 的 plugins 目录。重启 HanaAgent。

## 游戏内命令

| 命令 | 说明 |
|------|------|
| `/ai-status` | 查看 AI 角色状态 |
| `/ai-templates` | 列出建造模板 |
| `/ai-stop` | 紧急停止 |
| `/ai-reset` | 急停复位 |
| `/ai-mark [label]` | 标记区域 |

## 建造模板

- `smelter_row` — 电炉排（传送带+爪子+电线杆）
- `stone_furnace_row` — 石炉排
- `assembler_grid` — 组装机网格
- `miner_array` — 采矿机阵列
- `steam_power_unit` — 蒸汽发电单元
- `belt_bus` — 传送带总线
- `lab_cluster` — 实验室集群
- `wall_segment` — 墙壁段

## Mod 设置

进游戏后 Settings → Mod Settings → Map 标签页可调整：

- 虫子免疫
- 卡墙判定时间
- 批量建造速度
- 概览区块大小
- 调试模式

## HanaAgent 双 Profile

| Profile | 角色 | 工具数 | 模型建议 |
|---------|------|--------|----------|
| Planner | 规划 | 13 | 强推理模型 |
| Executor | 执行 | 14 | 便宜快速模型 |

## 项目结构

```
factorio-ai-builder/
├── mod/factorio-ai-builder/   # Factorio Lua Mod
│   ├── modules/               # 核心模块
│   ├── templates/             # 建造模板
│   └── locale/                # 中英文
├── bridge/                    # Python 桥接服务
├── plugins/ai-builder-hana/   # HanaAgent 插件
└── ARCHITECTURE.md            # 完整架构文档
```

## 技术要点

- **寻路**: Factorio 2.0 单位实体 + `commandable.set_command(go_to_location)`
- **物品栏**: 隐藏 character 实体 + `teleport` 瞬移
- **稀疏数据**: chunk 概览 + 实体压缩 + 区域标记
- **批量建造**: 模板展开 + 逐 tick 放置 + 障碍暂停/汇报

## 兼容性

- Factorio 2.0+
- Python 3.11+
- HanaAgent (插件) / 任意支持 HTTP API 的 Agent

## License

MIT
