# Factorio AI Builder — 实施方案

## 核心设计原则

对应你的七条需求：

1. **数据不是推给 AI，是 AI 主动拉**。AI 拿到的是摘要（坐标+物产），不是全量 dump。AI 可以丢弃自己标注过的缓存区域
2. **单角色**。一个 AI character，不污染游戏画面
3. **重复劳动脚本化**。铺设、连线、配方配置用脚本模板执行。障碍 = 暂停 = 问 AI
4. **急停**。物理切断。取消所有挂起操作，强制 character 停止
5. **虫子免疫**。AI character 在敌对生物面前无敌
6. **圈地查询**。AI 可以圈矩形区域要详情。玩家也可以圈地提交给 AI。数据强制压缩
7. **三层分离**。mod（Lua）→ 桥接服务（任意语言）→ 插件（HanaAgent / MCP / 任何 Agent）
8. **角色分离（非强制）**。推理模型做规划（贵但低频），勤杂模型做执行（便宜但高频）。两个模型可用不同 API / provider，节省成本

---

## 总体架构

```
┌──────────────────────────────────────────────────────┐
│  Plugin Layer (agent-specific)                       │
│  ├── Planner Profile (推理模型, 贵)                   │
│  │   └── 只读工具：概览、圈地、配方、科技、Agent状态  │
│  ├── Executor Profile (勤杂模型, 便宜)                │
│  │   └── 写工具：行走、挖掘、建造、批量、急停          │
│  ├── ai-builder-hana    HanaAgent 插件 (双 profile)   │
│  └── ai-builder-mcp     MCP server, 供 Claude 等使用  │
└──────────────────┬───────────────────────────────────┘
                   │ HTTP REST API
┌──────────────────▼───────────────────────────────────┐
│  Bridge Service (Python FastAPI, agent-agnostic)     │
│  ├── RCON 连接管理 (多包响应、重连)                   │
│  ├── 区域缓存 (AI 维护的稀疏空间索引)                │
│  ├── 批量模板库 (预定义建造模式)                     │
│  ├── 异步操作追踪 (行走、挖掘完成后回调)             │
│  └── 急停逻辑                                        │
└──────────────────┬───────────────────────────────────┘
                   │ RCON (TCP)
┌──────────────────▼───────────────────────────────────┐
│  Factorio Lua Mod: factorio-ai-builder               │
│  ├── agent.lua         单角色生命周期                │
│  ├── movement.lua      寻路 + 行走状态机             │
│  ├── placement.lua     实体放置校验                  │
│  ├── mining.lua        资源挖掘                      │
│  ├── inventory.lua     背包管理                      │
│  ├── crafting.lua      手搓队列                      │
│  ├── research.lua      科技管理                      │
│  ├── area_query.lua    区域标记 + 详细查询           │
│  ├── batch_builder.lua 批量建造引擎                  │
│  ├── emergency_stop.lua急停                          │
│  ├── biter_immunity.lua虫子无敌                      │
│  └── remote_interface.lua  ← 所有 remote.call() 入口  │
└──────────────────────────────────────────────────────┘
```

---

## 一、Factorio Lua Mod

项目名：`factorio-ai-builder`

目录结构：

```
factorio-ai-builder/
├── info.json
├── data.lua                  # 空或极小（不需要自定义原型）
├── control.lua               # 入口：注册事件、初始化全局状态
├── config.lua                # 常量：端口、默认力、调试开关
├── remote_interface.lua      # 所有 remote.call() 对外接口
├── modules/
│   ├── agent.lua
│   ├── movement.lua
│   ├── placement.lua
│   ├── mining.lua
│   ├── inventory.lua
│   ├── crafting.lua
│   ├── research.lua
│   ├── area_query.lua
│   ├── batch_builder.lua
│   ├── emergency_stop.lua
│   ├── biter_immunity.lua
│   └── utils.lua             # 序列化、方向计算、验证
└── templates/
    └── default.lua           # 预定义建造模板
```

### 1.1 Agent 模块 (`modules/agent.lua`)

**职责**：单角色生命周期。创建、销毁、状态查询。

```lua
-- 核心接口（通过 remote.call 调用）
agent.create(position)        → agent 已存在则返回错误
agent.destroy()               → 销毁角色，清理挂起操作
agent.get_state()             → {position, inventory_summary, current_action}
agent.get_inventory()         → 完整背包 [{name, count}]
agent.is_busy()               → 是否有挂起的异步操作
```

**实现要点**：
- 用 `game.surfaces[1].create_entity{name="character", position=..., force="player"}` 创建
- 不关联 player（`create_character()` 是给 player 用的，我们要的是独立 entity）
- 全局状态存在 `storage.agent` 表里，Factorio 自动持久化

### 1.2 移动模块 (`modules/movement.lua`)

**核心流程**（参考 fv_embodied_agent 的 walking.lua）：

```
1. AI 调用 walk_to({x, y})
2. mod 用 surface.request_path() 异步请求寻路
3. 监听 on_script_path_request_finished 事件
4. 在 on_tick 中逐帧沿路径点移动 character
   - 计算当前路点方向，设置 walking_state
   - 到达路点 → 弹出 → 瞄准下一个
   - 路点走完 → 完成
5. 卡墙角检测：连续 N tick 位置不变 → 重新寻路 → 仍失败 → 报告障碍位置给桥接
```

**接口**：
```lua
movement.walk_to(goal_position, strict_goal)
  → {queued=true, path_id="xxx"}
movement.stop()
  → 立即停止移动
movement.get_status()
  → {state="walking"|"arrived"|"stuck", position, remaining_waypoints}
```

**technical note**: character 不是 unit，不能用 `set_command()`。必须用 `walking_state` + `on_tick` 手动驱动。但 character 的 `walking_state` 对于无玩家关联的 character 是**持久化**的（设置一次会一直走，不像玩家角色每 tick 被输入覆盖），所以只需要在方向改变时更新 `walking_state`，不需要每 tick 都设。

### 1.3 放置模块 (`modules/placement.lua`)

单个实体放置：执行前校验（可放置、物品足够），创建实体，扣除背包。

```lua
placement.place_entity(entity_name, position, direction, options)
  → {placed=true, entity_unit_number}
placement.pickup_entity(position)
  → {picked_up=true, items=[...]}
placement.set_recipe(entity_name, position, recipe_name)
  → {configured=true}
```

### 1.4 批量建造引擎 (`modules/batch_builder.lua`)

**这是你这套方案的关键差异点。**

```lua
batch_builder.build(template_name, anchor_position, count, options)
  → {queued=true, batch_id="xxx", estimated_ticks}

batch_builder.get_batch_status(batch_id)
  → {
      state = "building" | "paused_obstacle" | "paused_missing_items" | "completed",
      progress = {built: 12, remaining: 28},
      obstacles = [{position, entity_name}],    -- 仅当 paused_obstacle 时有值
      missing_items = [{name, have, need}]      -- 仅当 paused_missing_items 时有值
    }

batch_builder.resume(batch_id, resolution)
  -- resolution: "skip_obstacles" | "destroy_obstacles" | "adjust_layout"
batch_builder.cancel(batch_id)
```

**模板定义**（`templates/default.lua`）：

```lua
-- 示例：一排 5 个电炉，带电线杆和爪子
templates.smelter_row = {
  name = "smelter_row",
  description = "一排电炉，输入输出传送带+爪子+中电线杆",
  -- entities 是相对坐标，anchor_position + offset = 实际位置
  entities = {
    -- 每个模板单元（1个熔炉+配套），repeat_x 表示水平重复间距
    {name="electric-furnace",         offset={0,0},   direction=0},
    {name="medium-electric-pole",     offset={0,-3},  direction=0},
    {name="fast-inserter",            offset={-1,1},  direction=4},  -- 输入
    {name="fast-inserter",            offset={1,1},   direction=0},  -- 输出
    {name="transport-belt",           offset={-2,1},  direction=0},  -- 输入线
    {name="transport-belt",           offset={2,1},   direction=0},  -- 输出线
  },
  repeat_x = 3,    -- 每个单元水平间隔 3 格
  repeat_y = 0,    -- 不纵向重复
  -- 需要 AI 在 build() 时传入的变量
  variables = {"recipe_name"},
  -- 建造顺序（先铺传送带，再放机器，再放爪子）
  build_order = {5,6, 1,2, 3,4},
}
```

**建造流程**：

```
1. 桥接服务调用 batch_builder.build("smelter_row", {x=100,y=100}, 8, {recipe_name="iron-plate"})
2. 模板展开：8 × repeat_x = 24 格宽，计算出 8 组实体的绝对坐标
3. 按 build_order 顺序逐个放置：
   a. pre-check: 位置是否可建？物品是否足够？
   b. 可建 → queue 到 on_tick 循环（每 tick 放 N 个，避免卡顿）
   c. 不可建（障碍）→ 暂停，标记障碍位置，设置 state="paused_obstacle"
   d. 缺材料 → 暂停，列出缺失物品，state="paused_missing_items"
4. 暂停后，桥接服务轮询 get_batch_status() 拿到 obstacles 或 missing_items
5. 桥接服务将障碍信息交给 AI
6. AI 决定 → 调用 resume(batch_id, "skip_obstacles") 或 "destroy_obstacles"
7. 继续建造直到完成
```

**关键参数**：
- `config.lua` 中 `BATCH_PLACEMENTS_PER_TICK = 3`：每 tick 最多放 3 个实体，避免服务器 lag
- 电线自动连接由 Factorio 引擎处理，不需要手写

### 1.5 区域查询模块 (`modules/area_query.lua`)

这是满足需求 1 和 6 的核心模块。

**两层表示法**：

```
Layer 1: 稀疏摘要（概览模式）
  → 粗粒度网格（如 32×32 chunk），每个 chunk 输出摘要：
    "chunk(6,4)": {iron-ore: 大量, stone: 少量, assemblers: 3, belts: ~50}

Layer 2: 详细查询（圈地模式）
  → AI 或玩家标记矩形区域后，输出该区域内所有实体详情
  → 但实体描述强制压缩（相同配方机器合并、相同传送带方向合并）
```

**接口**：

```lua
-- 概览：获取指定范围（如 192×192 区域）的 chunk 摘要
area_query.get_overview(center, radius_chunks)
  → {chunks: {"chunk(6,4)": {resources: {...}, buildings: {...}}, ...}}

-- 圈地标记（AI 或玩家创建）
area_query.create_mark(mark_id, corner1, corner2, label)
  → {marked: true}

-- 查询圈地详情（返回压缩后的实体列表）
area_query.get_mark_detail(mark_id)
  → {
      area: {x1, y1, x2, y2},
      label: "铁矿区",
      summary: {
        assemblers: [{recipe: "iron-gear-wheel", count: 4, positions: [...]}],
        furnaces:   [{recipe: "iron-plate", count: 8, positions: [...]}],
        belts:      [{direction: 0, count: 32, path: [[x1,y1], [x2,y2], ...]}],
        inserters:  [{type: "fast", count: 16, positions: [...]}],
        resources:  [{name: "iron-ore", estimated: 120000, positions: [[x,y], ...]}],
        power_poles: [{type: "medium", count: 6}],
      },
      raw_entity_count: 347,    -- 压缩前数量
      compressed_entity_count: 28, -- 压缩后条目数
    }

-- 删除标记（AI 主动清理缓存）
area_query.remove_mark(mark_id)

-- 列出所有标记
area_query.list_marks()
  → [{mark_id, corner1, corner2, label}]

-- 玩家圈地：用 selection-tool item 或聊天命令
-- /ai-mark <label>  → 标记当前选中的区域
```

**压缩策略**（运行在 Lua 侧，减少数据传输）：

```lua
-- 1. 相同类型+配方合并
assemblers → 按 recipe 分组，只输出 recipe + count + 位置数组

-- 2. 传送带链折叠
连续同方向的传送带 → 合并为路径线段 [{start, end, direction}]

-- 3. 电线杆按覆盖合并
同类型相邻电线杆 → 合并为覆盖区域

-- 4. 资源用 estimated 而非精确数量
矿石→ "estimated: ~120000"（用相邻 chunk 密度估算）
```

**数据量对比**：

```
未压缩：347 个实体 × 每个 ~80 bytes = ~28 KB
压缩后：28 条摘要 × 每条 ~120 bytes = ~3.4 KB
压缩比：~8:1
```

对于 AI（尤其是 API 调用的 LLM），3.4 KB 的 JSON 能在一次调用中处理，而 28 KB 可能已经影响响应质量。

### 1.6 急停模块 (`modules/emergency_stop.lua`)

```lua
emergency_stop.trigger()
  → 1. 取消所有挂起的批量建造
  → 2. 停止 character 移动 (walking_state = {walking=false})
  → 3. 清空挖掘队列
  → 4. 清空手搓队列
  → 5. 设置 storage.agent.emergency_stopped = true
  → 6. 返回 {stopped: true, cancelled_actions: ["batch_3", "walk_12"]}

emergency_stop.reset()
  → 清除急停标志，AI 可以重新发命令
```

**触发方式**：
- 桥接服务调用 `remote.call("ai_builder", "emergency_stop")`
- 同时在 Mod 中注册聊天命令 `/ai-stop`，玩家可以直接输入
- 桥接服务提供一个 HTTP endpoint：`POST /emergency-stop`

### 1.7 虫子免疫 (`modules/biter_immunity.lua`)

```lua
-- 在 control.lua 中注册事件
script.on_event(defines.events.on_entity_damaged, function(event)
  local entity = event.entity
  if entity == storage.agent.character then
    -- 检查伤害来源是否为敌对生物
    if event.cause and event.cause.force.name == "enemy" then
      -- 恢复 HP 到满
      entity.health = entity.prototype.max_health
      -- 可选：记录日志
      log("[AI Builder] Agent hit by biter, damage nullified")
    end
  end
end)
```

或者更简单的方式：

```lua
-- 创建 character 时设置
character.destructible = false  -- 不可被摧毁
-- 但 destructible 可能影响所有伤害类型，需要测试
```

如果 `destructible=false` 会阻止玩家正常交互（如拆除 character），则用事件过滤方案。

### 1.8 远程接口 (`remote_interface.lua`)

所有对外接口统一通过 Factorio 的 `remote` 系统暴露：

```lua
-- remote_interface.lua
local interface_name = "ai_builder"

remote.add_interface(interface_name, {
  -- Agent
  create_agent = function(position) ... end,
  destroy_agent = function() ... end,
  get_agent_state = function() ... end,
  
  -- Movement
  walk_to = function(goal, strict) ... end,
  stop_moving = function() ... end,
  
  -- Placement
  place_entity = function(name, pos, dir) ... end,
  pickup_entity = function(pos) ... end,
  set_recipe = function(name, pos, recipe) ... end,
  
  -- Mining
  mine_resource = function(name, max_count) ... end,
  
  -- Inventory
  get_inventory = function() ... end,
  insert_items = function(entity, pos, item, count) ... end,
  extract_items = function(entity, pos, item, count) ... end,
  
  -- Crafting
  craft_enqueue = function(recipe, count) ... end,
  
  -- Research
  enqueue_research = function(tech) ... end,
  get_technologies = function(available_only) ... end,
  
  -- Batch
  batch_build = function(template, anchor, count, opts) ... end,
  get_batch_status = function(batch_id) ... end,
  resume_batch = function(batch_id, resolution) ... end,
  cancel_batch = function(batch_id) ... end,
  
  -- Area query
  get_overview = function(center, radius) ... end,
  create_mark = function(mark_id, c1, c2, label) ... end,
  get_mark_detail = function(mark_id) ... end,
  remove_mark = function(mark_id) ... end,
  list_marks = function() ... end,
  
  -- Emergency
  emergency_stop = function() ... end,
  reset_emergency = function() ... end,
})
```

RCON 调用方式：

```
# 创建 agent
/c remote.call("ai_builder", "create_agent", {x=0, y=0})

# 批量建造
/c remote.call("ai_builder", "batch_build", "smelter_row", {x=100, y=100}, 8, {recipe_name="iron-plate"})

# 圈地查询
/c remote.call("ai_builder", "create_mark", "zone_1", {x=80, y=80}, {x=120, y=120}, "smelting_area")
/c remote.call("ai_builder", "get_mark_detail", "zone_1")
```

---

## 二、桥接服务 (Bridge Service)

**语言**：Python 3.11+ / FastAPI
**运行位置**：和 HanaAgent 同一台机器（或局域网内任意机器）

### 2.1 RCON 连接层

```python
# rcon_client.py
import factorio_rcon
import asyncio

class FactorioRCON:
    def __init__(self, host, port, password):
        self.client = factorio_rcon.RCONClient(host, port, password)
    
    async def execute(self, lua_code: str) -> str:
        """发送 Lua 代码，返回响应。自动处理多包响应。"""
        # factorio-rcon-py 已处理多包响应（>64KB 的响应会自动合并）
        return await self.client.send_command(f"/c {lua_code}")
    
    async def remote_call(self, interface: str, method: str, *args):
        """调用 mod 的远程接口"""
        # 序列化参数为 Lua 可读格式
        lua_args = self._serialize_args(args)
        code = f'remote.call("{interface}", "{method}", {lua_args})'
        result = await self.execute(code)
        return self._parse_response(result)
```

### 2.2 区域缓存管理

```python
# area_cache.py
class AreaCache:
    """
    AI 维护的稀疏空间索引。
    
    不是全局缓存——只存 AI 明确请求过的区域。
    AI 可以：
    - mark_area() → 查询一个区域，加入缓存
    - unmark_area() → 从缓存中删除
    - list_marked() → 查看自己标记了哪些区域
    
    缓存与 Mod 侧的 mark 同步：
    Mod 存详细实体数据，桥接存摘要 + ttl。
    """
    
    def __init__(self):
        self.marks = {}  # {mark_id: {area, label, detail, cached_at}}
        self.ttl = 300    # 5 分钟后自动过期，强制 AI 重新查询
    
    def add(self, mark_id, area, label, detail):
        self.marks[mark_id] = {...}
    
    def remove(self, mark_id):
        # 同时通知 Mod 侧删除（可选，Mod 侧 mark 也可以留着）
        ...
    
    def get_stale_marks(self):
        """返回过期的标记，提示 AI 清理"""
        ...
```

### 2.3 异步操作管理

```python
# async_ops.py
class AsyncOperationManager:
    """
    管理行走、挖掘等异步操作。
    
    流程：
    1. AI 调用 POST /agent/walk {goal: {x,y}}
    2. 桥接发送 RCON 命令，获得 action_id
    3. 启动后台轮询任务，每 500ms 检查 agent.get_state()
    4. 状态变为 "arrived" → 回调 / 标记完成
    5. 状态变为 "stuck" → 返回障碍信息
    
    实现：FastAPI BackgroundTasks + asyncio
    """
```

### 2.4 HTTP API 设计

```
Base URL: http://localhost:9380/api/v1

# ---- 连接管理 ----
GET  /health
      → {connected: true, game_tick: 1234567, surface: "nauvis"}

# ---- Agent ----
POST /agent/create        {position: {x, y}}
      → {created: true, agent_position: {x, y}}
POST /agent/destroy
      → {destroyed: true}
GET  /agent/state
      → {position, inventory_summary, current_action, is_busy}

# ---- 移动 ----
POST /agent/walk          {goal: {x, y}, strict_goal: false}
      → {queued: true, action_id: "walk_abc123"}
GET  /agent/walk/{action_id}/status
      → {state: "walking"|"arrived"|"stuck", 
         stuck_position: null|{x,y}}
POST /agent/stop
      → {stopped: true}

# ---- 建造 ----
POST /agent/build/single  {entity_name, position, direction}
      → {placed: true}
POST /agent/build/batch   {template_name, anchor: {x,y}, count, options}
      → {queued: true, batch_id: "batch_abc123"}
GET  /agent/build/batch/{batch_id}
      → {state, progress, obstacles?: [...], missing_items?: [...]}
POST /agent/build/batch/{batch_id}/resume  {resolution: "skip_obstacles"}
      → {resumed: true}
POST /agent/build/batch/{batch_id}/cancel
      → {cancelled: true}

# ---- 挖掘 ----
POST /agent/mine          {resource_name: "iron-ore", max_count: 50}
      → {queued: true, action_id: "mine_abc123"}

# ---- 区域查询 ----
GET  /world/overview?center_x=100&center_y=100&radius_chunks=3
      → {chunks: {...}}
POST /world/mark          {mark_id, corner1: {x,y}, corner2: {x,y}, label}
      → {marked: true}
GET  /world/mark/{mark_id}
      → {area, label, summary: {...}}
DELETE /world/mark/{mark_id}
      → {removed: true}
GET  /world/marks
      → {marks: [...]}

# ---- 紧急 ----
POST /emergency-stop
      → {stopped: true, cancelled: ["batch_3", "walk_12"]}
POST /emergency-reset
      → {reset: true}

# ---- 科技 ----
GET  /technologies?available_only=true
      → {technologies: [...]}
POST /research/enqueue   {technology_name}
      → {queued: true}

# ---- 物品/配方查询 ----
GET  /recipes
      → {recipes: [{name, ingredients, products}]}
GET  /agent/inventory
      → {items: [{name, count}]}
```

### 2.5 批量操作与 AI 交互的核心流程

这是需求 3 的关键实现：

```
AI: "在 (100, 200) 建 8 个铁板熔炉"

Bridge:
  1. POST /agent/walk {goal: {x:100, y:200}}     → action_id: walk_1
  2. 轮询直到 arrived
  
  3. POST /world/mark {
       mark_id: "pre_build_check",
       corner1: {x:90, y:190},
       corner2: {x:130, y:220},
       label: "预建区域检查"
     }
  4. GET /world/mark/pre_build_check
     → 检查区域是否有障碍、资源覆盖等
  
  5. AI 审核区域详情，确认可以建造
  
  6. POST /agent/build/batch {
       template_name: "smelter_row",
       anchor: {x:100, y:200},
       count: 8,
       options: {recipe_name: "iron-plate"}
     }                                                → batch_id: batch_1
  
  7. 轮询 GET /agent/build/batch/batch_1
     
     情况 A: state = "paused_obstacle"
       obstacles = [{position: {x:112, y:203}, entity_name: "stone-rock"}]
       → Bridge 将障碍信息发给 AI
       → AI 决定：
         a. "skip_obstacles" → 跳过这个位置，熔炉往旁边移一格
         b. "destroy_obstacles" → 先挖掉石头再继续
         c. "adjust_layout" → 重新设计布局
       → POST /agent/build/batch/batch_1/resume {resolution: "skip_obstacles"}
     
     情况 B: state = "paused_missing_items"
       missing_items = [{name: "electric-furnace", have: 3, need: 8}]
       → Bridge 将缺料信息发给 AI
       → AI 决定：暂停建造手搓熔炉 / 标记缺口后继续建造其他部分
  
  8. state = "completed" → 完成
```

---

## 三、插件层

### 3.1 HanaAgent 插件 (`ai-builder-hana`)

用 `hana-plugin-creator` 的 `--kind tool` 模板生成，`tools/` 目录下每个 HTTP API 对应一个工具文件。

示例 `tools/factorio_walk_to.js`：

```javascript
export const name = "factorio_walk_to";
export const description = "控制 AI 角色走到指定坐标。";

export const parameters = {
  type: "object",
  properties: {
    x: { type: "number", description: "目标 X 坐标" },
    y: { type: "number", description: "目标 Y 坐标" },
  },
  required: ["x", "y"],
};

export async function execute(params, ctx) {
  const response = await fetch("http://localhost:9380/api/v1/agent/walk", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ goal: { x: params.x, y: params.y } }),
  });
  const result = await response.json();
  
  if (result.queued) {
    // 轮询等待到达
    let status;
    do {
      await sleep(500);
      const s = await fetch(`http://localhost:9380/api/v1/agent/walk/${result.action_id}/status`);
      status = await s.json();
    } while (status.state === "walking");
    
    return {
      arrived: status.state === "arrived",
      position: status.position,
      stuck: status.state === "stuck" ? status.stuck_position : null,
    };
  }
  
  return { error: "walk command failed" };
}
```

**工具列表**（照搬 HTTP API 的 POST/GET 端点）：

| 工具名 | 对应 API |
|--------|----------|
| `factorio_get_overview` | GET /world/overview |
| `factorio_mark_area` | POST /world/mark |
| `factorio_get_area_detail` | GET /world/mark/{id} |
| `factorio_unmark_area` | DELETE /world/mark/{id} |
| `factorio_walk_to` | POST /agent/walk |
| `factorio_mine` | POST /agent/mine |
| `factorio_place_entity` | POST /agent/build/single |
| `factorio_build_batch` | POST /agent/build/batch |
| `factorio_check_batch` | GET /agent/build/batch/{id} |
| `factorio_resume_batch` | POST /agent/build/batch/{id}/resume |
| `factorio_cancel_batch` | POST /agent/build/batch/{id}/cancel |
| `factorio_emergency_stop` | POST /emergency-stop |
| `factorio_get_agent_state` | GET /agent/state |
| `factorio_craft` | POST /agent/craft |
| `factorio_get_technologies` | GET /technologies |
| `factorio_start_research` | POST /research/enqueue |
| `factorio_get_recipes` | GET /recipes |

### 3.2 MCP Server（可选，供 Claude Code 等使用）

桥接服务本身可以内嵌一个 MCP server，或者单独发布一个 MCP 包。

MCP Server 的工具直接映射到 HTTP API，与 HanaAgent 插件共享同一套后端。这样一次开发，多个 Agent 都能用。

MCP 工具定义示例（`mcp_server.py` 片段）：

```python
# 用 FastMCP 库
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Factorio AI Builder")

@mcp.tool()
async def factorio_get_overview(center_x: int, center_y: int, radius_chunks: int = 3):
    """获取指定区域的大致资源与建筑摘要"""
    ...

@mcp.tool()
async def factorio_build_batch(
    template_name: str,
    anchor_x: int,
    anchor_y: int,
    count: int,
    recipe_name: str = None
):
    """使用预定义模板批量建造。可用模板: smelter_row, assembler_grid..."""
    ...
```

---

## 四、角色分离架构（成本优化）

### 4.1 为什么需要两个角色

Factorio 的 AI 交互天然分两层：

| | 推理层 (Planner) | 执行层 (Executor) |
|---|---|---|
| **频率** | 低（几分钟一次） | 高（每秒轮询） |
| **Token 消耗** | 高（需要理解工厂全貌、配方链） | 低（读状态、点按钮） |
| **模型要求** | 需要强推理能力 | 需要可靠、速度快 |
| **典型操作** | 决定在哪建什么、优化方案 | 走路、放实体、检查批量状态 |
| **适用 API** | GPT-4 / Claude Sonnet / DeepSeek-Pro | DeepSeek-Flash / GPT-4o-mini |

用同一个模型做两件事 = 为"检查批量建造进度是否完成"支付推理级模型的费用。

### 4.2 工具分家

桥接服务的 HTTP API 不变，但插件层按 profile 过滤工具：

**Planner Profile（推理模型可见）——只读 + 规划**：

```
factorio_get_overview        概览区域摘要
factorio_mark_area            圈地标记
factorio_get_area_detail      查询圈地详情
factorio_unmark_area          删除标记（清理缓存）
factorio_list_marks           列出已有标记
factorio_get_agent_state      查角色状态
factorio_get_recipes          查配方
factorio_get_technologies     查科技树
factorio_get_inventory        查背包
factorio_start_research       开始研究（规划的一部分）
factorio_craft                手搓（规划需要的物品）
```

**Executor Profile（勤杂模型可见）——写入 + 轮询**：

```
factorio_walk_to              走到指定坐标
factorio_stop                 停止移动
factorio_mine                 挖掘资源
factorio_place_entity         放置单个实体
factorio_pickup_entity        捡起实体
factorio_set_recipe           设置机器配方
factorio_insert_items         放入物品
factorio_extract_items        取出物品
factorio_build_batch          发起批量建造
factorio_check_batch          查询批量进度
factorio_resume_batch         恢复批量（障碍决策）
factorio_cancel_batch         取消批量
factorio_get_agent_state      查角色状态（执行需要知道是否到达）
factorio_emergency_stop       急停
factorio_emergency_reset      急停复位
```

注意 `factorio_get_agent_state` 两边都有：Planner 需要知道角色在哪、规划是否需要移动，Executor 需要知道行走是否到达。

### 4.3 角色间的通信协议

两个角色不直接对话（避免 token 浪费），通过**共享工作区文件**交换结构化数据：

```
factorio-ai-builder/
├── workspace/
│   ├── plan.json          ← Planner 输出，Executor 读取
│   ├── report.json        ← Executor 输出，Planner 读取
│   └── emergency.json     ← 急停信号
```

**plan.json 格式**（Planner → Executor）：

```json
{
  "plan_id": "plan_20260530_001",
  "created_at": "2026-05-30T17:42:00+08:00",
  "status": "pending",
  "steps": [
    {
      "id": 1,
      "type": "walk",
      "goal": {"x": 100, "y": 200},
      "reason": "移动到预设建造点"
    },
    {
      "id": 2,
      "type": "mark_area",
      "mark_id": "build_site_1",
      "corner1": {"x": 90, "y": 190},
      "corner2": {"x": 150, "y": 250},
      "label": "建造区域检查"
    },
    {
      "id": 3,
      "type": "query_area",
      "mark_id": "build_site_1",
      "reason": "确认该区域是否适合建造"
    },
    {
      "id": 4,
      "type": "build_batch",
      "template": "smelter_row",
      "anchor": {"x": 100, "y": 200},
      "count": 8,
      "options": {"recipe_name": "iron-plate"},
      "depends_on": [3],
      "on_obstacle": "report_to_planner"
    }
  ]
}
```

**report.json 格式**（Executor → Planner）：

```json
{
  "plan_id": "plan_20260530_001",
  "completed_steps": [1, 2, 3],
  "current_step": 4,
  "current_step_status": {
    "state": "paused_obstacle",
    "batch_id": "batch_abc123",
    "obstacles": [
      {"position": {"x": 112, "y": 203}, "entity_name": "stone-rock"}
    ]
  },
  "agent_state": {
    "position": {"x": 105, "y": 205},
    "inventory_summary": {"electric-furnace": 5, "medium-electric-pole": 3}
  },
  "requested_action": "resolve_obstacle",
  "timestamp": "2026-05-30T17:43:15+08:00"
}
```

### 4.4 交互流程

```
用户：在我的铁矿旁边建一排熔炉

[Planner - 推理模型, 贵]
  1. factorio_get_overview(center_x=..., center_y=..., radius_chunks=3)
     → 发现 chunk(6,4) 有大量铁矿，chunk(7,4) 有空地
  2. factorio_get_recipes
     → 确认 iron-plate 配方可用
  3. factorio_get_agent_state
     → 角色在 (50, 50)，需要走过去
  4. 输出 plan.json：走到 (100,200)，圈地检查，建 8 个熔炉
  → 只用了 ~3 次 API 调用，~5K tokens

[Executor - 勤杂模型, 便宜]
  1. 读 plan.json
  2. factorio_walk_to(100, 200) → 轮询直到到达
  3. factorio_mark_area("build_site_1", ...) → factorio_get_area_detail → 可建造
  4. factorio_build_batch("smelter_row", ...)
  5. 每 1 秒轮询 factorio_check_batch
  
  遇到障碍 → 写 report.json，设置 requested_action: "resolve_obstacle"
  
[Planner 再次介入]
  1. 读 report.json
  2. 看到石头在 (112, 203)
  3. 决定：skip_obstacles（跳过那个位置，熔炉往旁边错开一格）
  4. 更新 plan.json step 4 增加 options.obstacle_resolution: "skip"

[Executor 继续]
  1. factorio_resume_batch("batch_abc123", "skip_obstacles")
  2. 继续轮询直到完成
  3. 写 report.json：完成
```

### 4.5 HanaAgent 映射

你的团队里已经有天然的角色对应：

| HanaAgent 子代理 | 角色 | 建议模型 | Factorio 职责 |
|---|---|---|---|
| `ming` (推理) | Planner | deepseek-v4-flash 或更强 | 读 plan.json → 决策 → 更新 plan.json |
| `janitor` (勤杂工) | Executor | deepseek-v4-flash 或更便宜 | 读 plan.json → 执行 → 写 report.json |

**HanaAgent 插件实现**：

插件注册两套工具集，通过 `manifest.json` 的 `capabilities` 字段声明：

```json
{
  "name": "factorio-ai-builder",
  "capabilities": {
    "profiles": {
      "planner": {
        "description": "Factorio 规划角色 - 查看地图、设计方案",
        "tools": [
          "factorio_get_overview",
          "factorio_mark_area",
          "factorio_get_area_detail",
          "factorio_unmark_area",
          "factorio_list_marks",
          "factorio_get_agent_state",
          "factorio_get_recipes",
          "factorio_get_technologies",
          "factorio_get_inventory",
          "factorio_start_research",
          "factorio_craft"
        ]
      },
      "executor": {
        "description": "Factorio 执行角色 - 行走、建造、挖掘",
        "tools": [
          "factorio_walk_to",
          "factorio_stop",
          "factorio_mine",
          "factorio_place_entity",
          "factorio_pickup_entity",
          "factorio_set_recipe",
          "factorio_insert_items",
          "factorio_extract_items",
          "factorio_build_batch",
          "factorio_check_batch",
          "factorio_resume_batch",
          "factorio_cancel_batch",
          "factorio_get_agent_state",
          "factorio_emergency_stop",
          "factorio_emergency_reset"
        ]
      }
    }
  }
}
```

HanaAgent 中用户可以用 `subagent` 工具分别调用：

```
用户：帮我建一排熔炉在铁矿旁边

→ ming (Planner) 被调用：调查、规划、写 plan.json
→ janitor (Executor) 被调用：读 plan.json，逐步执行
→ 遇到障碍 → janitor 写 report.json，系统通知用户
→ 用户或自动触发 ming 再次介入
```

### 4.6 成本估算

假设一个典型的"建一排熔炉"任务：

| 操作 | Planner 调用 | Executor 调用 |
|---|---|---|
| 概览查询 | 1 次 (~2K tokens) | |
| 配方查询 | 1 次 (~500 tokens) | |
| 规划输出 | 1 次 (~1K tokens) | |
| 行走 | | 1 次 + 3-5 次轮询 (~3K tokens) |
| 圈地查询 | | 1 次 (~1K tokens) |
| 批量建造 | | 1 次 + 20-30 次轮询 (~5K tokens) |
| **合计** | **~3.5K tokens (贵模型)** | **~9K tokens (便宜模型)** |

如果用单一模型：~12.5K tokens 全按贵模型算。
角色分离后：贵模型 3.5K + 便宜模型 9K = 节省约 60% 推理成本。

### 4.7 非强制实现

角色分离是可选优化。插件支持两种模式：

1. **统一模式**（默认）：所有工具暴露给一个 Agent，适合快速原型
2. **分离模式**：按 profile 划分，适合长期运行、频繁交互的场景

桥接服务完全不需要感知这个区别——它只管执行 HTTP API 调用，不管调用来自哪个角色。

---

## 五、实施阶段

### Phase 1：Factorio Mod 原型（5-7 天）

**目标**：在 Factorio 中手动 RCON 调用能创建角色、走路、放东西、查区域

- [ ] `info.json`, `control.lua`, `config.lua` 骨架
- [ ] `agent.lua`：创建/销毁/状态查询
- [ ] `movement.lua`：寻路+行走状态机
- [ ] `placement.lua`：单实体放置+挖掘
- [ ] `area_query.lua`：区域摘要+标记+详情查询
- [ ] `remote_interface.lua`：所有接口注册
- [ ] 测试：`/c remote.call("ai_builder", "create_agent", {x=0,y=0})`

### Phase 2：批量建造 + 急停 + 虫子免疫（3-4 天）

- [ ] `batch_builder.lua`：模板定义、展开、逐 tick 放置、障碍检测
- [ ] `templates/default.lua`：至少 5 个常用模板（熔炉排、组装机网格、传送带总线、采矿机阵列、发电机组）
- [ ] `emergency_stop.lua`
- [ ] `biter_immunity.lua`
- [ ] 测试：批量建 8 个熔炉，中间手动放石头，验证暂停+报告+恢复

### Phase 3：桥接服务（3-4 天）

- [ ] Python FastAPI 项目脚手架
- [ ] RCON 连接层
- [ ] HTTP API 全部端点
- [ ] 异步操作轮询（walk/mine 状态追踪）
- [ ] 区域缓存
- [ ] 端到端测试：HTTP API → RCON → Factorio → 角色走路

### Phase 4：插件层（2-3 天）

- [ ] HanaAgent 插件生成（`hana-plugin-creator`）
- [ ] 所有 tool JS 文件编写
- [ ] MCP Server（可选）
- [ ] 端到端：HanaAgent 对话 → 插件 tool → 桥接 → Factorio

### Phase 5：打磨（持续）

- [ ] 错误处理完善（Factorio 崩溃恢复、RCON 断开重连）
- [ ] 更多建造模板
- [ ] AI prompt 优化（system prompt 中嵌入模板说明、数据压缩指引）
- [ ] 性能：大规模批量建造的 tick 预算控制

---

## 六、技术风险与缓解

| 风险 | 概率 | 缓解 |
|------|------|------|
| RCON 大响应被截断 | 中 | factorio-rcon-py 已处理多包合并。再加超时+重试 |
| 寻路在大距离下延迟高 | 中 | 预设路径点分段寻路；加入 teleport 作为 fallback |
| character 卡墙角无法检测 | 中 | on_tick 中检测连续 N tick 位置不变 + walking_state 为 walking，判定为卡住 |
| 批量建造大量实体导致 tick 延迟 | 低 | `BATCH_PLACEMENTS_PER_TICK = 3`，可动态调整 |
| AI 频繁查询全图导致 token 爆炸 | 低 | 概览模式强制 chunk 摘要；详情模式强制实体压缩；cache 5 分钟 TTL |
| Mod 与 Factorio 版本不兼容 | 低 | 目标 Factorio 2.0+，API 相对稳定 |

---

## 七、目录规划

```
factorio-ai-builder/           ← 根目录
├── ARCHITECTURE.md            ← 本文档
├── mod/
│   └── factorio-ai-builder/   ← Factorio mod（放入 mods/ 目录即可）
│       ├── info.json
│       ├── data.lua
│       ├── control.lua
│       ├── config.lua
│       ├── remote_interface.lua
│       ├── modules/
│       └── templates/
├── bridge/                    ← Python 桥接服务
│   ├── main.py
│   ├── rcon_client.py
│   ├── area_cache.py
│   ├── async_ops.py
│   ├── api/
│   │   ├── agent.py
│   │   ├── world.py
│   │   └── emergency.py
│   ├── mcp_server.py          ← 可选 MCP Server
│   └── requirements.txt
├── plugins/
│   ├── ai-builder-hana/       ← HanaAgent 插件
│   │   ├── manifest.json
│   │   └── tools/
│   └── ai-builder-mcp/        ← MCP 插件（供外部 Agent 使用）
│       └── ...
└── README.md
```
