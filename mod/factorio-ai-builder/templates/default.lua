--[[
  Factorio AI Builder - Building Templates
  Predefined construction patterns for batch building.

  Each template defines:
  - name: unique identifier
  - description: human-readable explanation
  - entities: array of {name, offset, direction} relative to anchor
  - repeat_x, repeat_y: spacing between repeated copies
  - build_order: [indices] optimal placement sequence

  Offset system:
  - offset = {dx, dy} relative to anchor point
  - direction: Factorio direction (0=north, 2=east, 4=south, 6=west)
--]]

local templates = {}

-- ============================================================================
-- Smelter Row
-- ============================================================================

templates.smelter_row = {
  name = "smelter_row",
  description = "一排电炉，带输入输出传送带+爪子+中电线杆",
  variables = { "recipe_name" },
  repeat_x = 5,        -- 每个熔炉单元水平间距 5 格
  repeat_y = 0,
  entities = {
    -- 布局 (单单元):
    --   [电线杆] (y=-3)
    --   [入爪] ← [输入带] (y=-1, y=-2)
    --   [电炉] (y=0)
    --   [出爪] → [输出带] (y=1, y=2)

    { name = "electric-furnace",     offset = { 0,  0 }, direction = 0 },
    { name = "medium-electric-pole", offset = { 0, -3 }, direction = 0 },
    { name = "fast-inserter",        offset = { -2, -1 }, direction = 4 },  -- 从传送带到熔炉
    { name = "fast-inserter",        offset = { 2,  1 }, direction = 0 },   -- 从熔炉到传送带
    { name = "transport-belt",       offset = { -3, -1 }, direction = 0 },  -- 输入传送带
    { name = "transport-belt",       offset = { 3,  1 }, direction = 0 },   -- 输出传送带
    -- 额外传送带延伸
    { name = "transport-belt",       offset = { -4, -1 }, direction = 0 },
    { name = "transport-belt",       offset = { 4,  1 }, direction = 0 },
  },
  build_order = { 5, 6, 7, 8, 2, 1, 3, 4 },  -- 先铺传送带，再放电线杆，再熔炉，再爪子
}

-- ============================================================================
-- Stone Furnace Row (early game)
-- ============================================================================

templates.stone_furnace_row = {
  name = "stone_furnace_row",
  description = "一排石炉，带输入输出传送带+黄爪+小电线杆",
  variables = { "recipe_name" },
  repeat_x = 4,
  repeat_y = 0,
  entities = {
    { name = "stone-furnace",         offset = { 0,  0 }, direction = 0 },
    { name = "small-electric-pole",   offset = { 0, -2 }, direction = 0 },
    { name = "inserter",              offset = { -1, -1 }, direction = 4 },
    { name = "inserter",              offset = { 1,  1 }, direction = 0 },
    { name = "transport-belt",        offset = { -2, -1 }, direction = 0 },
    { name = "transport-belt",        offset = { 2,  1 }, direction = 0 },
  },
  build_order = { 5, 6, 2, 1, 3, 4 },
}

-- ============================================================================
-- Assembler Grid (2D array of assemblers with power)
-- ============================================================================

templates.assembler_grid = {
  name = "assembler_grid",
  description = "组装机网格布局 (rows × cols)，自动配中电线杆",
  variables = { "recipe_name", "rows", "cols" },
  repeat_x = 5,
  repeat_y = 5,
  entities = {
    -- 单个格子: 组装机 + 四个方向留爪子位
    -- 电线杆放在格子之间共享
    { name = "assembling-machine-2", offset = { 0,  0 }, direction = 0 },
    -- 电线杆 (间隔放置，每 2 个格子一个)
    { name = "medium-electric-pole", offset = { -3, -3 }, direction = 0 },
  },
  build_order = { 2, 1 },
}

-- ============================================================================
-- Miner Array
-- ============================================================================

templates.miner_array = {
  name = "miner_array",
  description = "采矿机阵列，带输出传送带和电线杆",
  variables = {},
  repeat_x = 5,
  repeat_y = 0,
  entities = {
    { name = "electric-mining-drill", offset = { 0,  0 }, direction = 0 },
    { name = "transport-belt",        offset = { 0,  2 }, direction = 0 },
    { name = "medium-electric-pole",  offset = { 2,  0 }, direction = 0 },
  },
  build_order = { 2, 3, 1 },
}

-- ============================================================================
-- Power Generation (Steam)
-- ============================================================================

templates.steam_power_unit = {
  name = "steam_power_unit",
  description = "蒸汽发电单元: 1锅炉 + 2蒸汽机 + 管道",
  variables = {},
  repeat_x = 6,
  repeat_y = 0,
  entities = {
    { name = "boiler",          offset = { 0,  0 }, direction = 0 },
    { name = "steam-engine",    offset = { 0,  2 }, direction = 0 },
    { name = "steam-engine",    offset = { 0,  4 }, direction = 0 },
    { name = "pipe",            offset = { 0,  1 }, direction = 0 },
    { name = "pipe",            offset = { 0,  3 }, direction = 0 },
    { name = "small-electric-pole", offset = { 2,  0 }, direction = 0 },
  },
  build_order = { 1, 4, 2, 5, 3, 6 },
}

-- ============================================================================
-- Belt Bus Segment
-- ============================================================================

templates.belt_bus = {
  name = "belt_bus",
  description = "平行传送带总线 (4 条)",
  variables = { "lane_count" },  -- default 4
  repeat_x = 1,   -- extending along x axis
  repeat_y = 0,
  entities = {
    { name = "transport-belt", offset = { 0,  0 }, direction = 0 },
    { name = "transport-belt", offset = { 0,  1 }, direction = 0 },
    { name = "transport-belt", offset = { 0,  2 }, direction = 0 },
    { name = "transport-belt", offset = { 0,  3 }, direction = 0 },
    -- Underground belt pair for crossing
    { name = "underground-belt", offset = { 0, -1 }, direction = 0, type = "input" },
    { name = "underground-belt", offset = { 4, -1 }, direction = 0, type = "output" },
    -- Splitter for lane balancing
    { name = "splitter",         offset = { 1, -1 }, direction = 0 },
  },
  repeat_y = 4,  -- 4 lanes spaced vertically
  build_order = { 1, 2, 3, 4, 5, 7, 6 },
}

-- ============================================================================
-- Lab Cluster
-- ============================================================================

templates.lab_cluster = {
  name = "lab_cluster",
  description = "实验室集群，带爪子互传",
  variables = {},
  repeat_x = 4,
  repeat_y = 4,
  entities = {
    { name = "lab",                 offset = { 0,  0 }, direction = 0 },
    { name = "inserter",            offset = { 1,  0 }, direction = 2 },
    { name = "medium-electric-pole", offset = { 2,  0 }, direction = 0 },
  },
  build_order = { 1, 3, 2 },
}

-- ============================================================================
-- Wall Segment
-- ============================================================================

templates.wall_segment = {
  name = "wall_segment",
  description = "墙壁段: 石墙+炮塔",
  variables = {},
  repeat_x = 2,
  repeat_y = 0,
  entities = {
    { name = "stone-wall",     offset = { 0, 0 }, direction = 0 },
    { name = "stone-wall",     offset = { 0, 1 }, direction = 0 },
    { name = "gun-turret",     offset = { 0, 2 }, direction = 0 },
  },
  build_order = { 1, 2, 3 },
}

-- ============================================================================
-- Template Registry
-- ============================================================================

function templates.get(name)
  return templates[name]
end

function templates.list()
  local names = {}
  for name, _ in pairs(templates) do
    if type(templates[name]) == "table" and templates[name].name then
      table.insert(names, name)
    end
  end
  table.sort(names)
  return names
end

function templates.list_with_descriptions()
  local result = {}
  for _, name in ipairs(templates.list()) do
    local t = templates[name]
    table.insert(result, {
      name = t.name,
      description = t.description,
      variables = t.variables or {},
      repeats_per_unit = { x = t.repeat_x or 0, y = t.repeat_y or 0 },
      entity_count_per_unit = #t.entities,
    })
  end
  return result
end

return templates
