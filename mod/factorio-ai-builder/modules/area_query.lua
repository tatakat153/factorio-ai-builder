--[[
  Factorio AI Builder - Area Query Module
  Sparse perception: chunk overviews and zone-based detailed queries.
  Core of the "sparse data" requirement.

  Two-layer representation:
  Layer 1: Overview (chunk-level summaries)
    → Chunks are config.OVERVIEW_CHUNK_SIZE × config.OVERVIEW_CHUNK_SIZE tiles
    → Each chunk returns: resource presence, building counts, belt estimates

  Layer 2: Mark detail (rectangle zone, compressed)
    → AI or player marks a rectangular area
    → get_mark_detail returns compressed entity list
    → Similar entities merged (e.g., 8 identical furnaces → 1 entry)

  Compression strategies:
  - Assemblers/furnaces: group by recipe, output count + positions
  - Belts: collapse consecutive same-direction belts into path segments
  - Inserters: group by type
  - Power poles: group by type + coverage
  - Resources: estimated amount (not exact count)
--]]

local config = require("__factorio-ai-builder__/config")
local utils = require("__factorio-ai-builder__/modules/utils")
local agent = require("__factorio-ai-builder__/modules/agent")

local area_query = {}

-- ============================================================================
-- Layer 1: Overview (Chunk Summary)
-- ============================================================================

function area_query.get_overview(center, radius_chunks)
  if not game.surfaces[1] then
    return nil, "no_surface"
  end

  local surface = game.surfaces[1]
  local c = utils.table_to_position(center) or { x = 0, y = 0 }
  local r = radius_chunks or 3

  local chunk_size = config.OVERVIEW_CHUNK_SIZE
  local chunks = {}

  for cx = -r, r do
    for cy = -r, r do
      local chunk_key = "(" .. cx .. "," .. cy .. ")"
      local area = {
        { c.x + cx * chunk_size, c.y + cy * chunk_size },
        { c.x + (cx + 1) * chunk_size, c.y + (cy + 1) * chunk_size },
      }

      local summary = area_query._summarize_chunk(surface, area)

      -- Only include non-empty chunks
      if summary.resource_count > 0 or summary.building_count > 0 then
        chunks[chunk_key] = summary
      end
    end
  end

  return {
    center = c,
    chunk_size = chunk_size,
    radius_chunks = r,
    chunks = chunks,
    total_chunks = (2 * r + 1) ^ 2,
    non_empty_chunks = table_size(chunks),
  }
end

function area_query._summarize_chunk(surface, area)
  local entities = surface.find_entities_filtered { area = area }

  local resources = {}
  local buildings = {}
  local belt_count = 0
  local inserter_count = 0
  local power_pole_count = 0
  local assembler_count = 0
  local furnace_count = 0
  local miner_count = 0

  for _, entity in ipairs(entities) do
    local etype = entity.type

    if etype == "resource" then
      local name = entity.name
      if not resources[name] then
        resources[name] = { count = 0, estimated_amount = 0 }
      end
      resources[name].count = resources[name].count + 1
      resources[name].estimated_amount = resources[name].estimated_amount +
        (entity.amount or 1000)

    elseif etype == "assembling-machine" then
      assembler_count = assembler_count + 1
      if not buildings.assemblers then buildings.assemblers = 0 end
      buildings.assemblers = buildings.assemblers + 1

    elseif etype == "furnace" then
      furnace_count = furnace_count + 1
      if not buildings.furnaces then buildings.furnaces = 0 end
      buildings.furnaces = buildings.furnaces + 1

    elseif etype == "mining-drill" then
      miner_count = miner_count + 1
      if not buildings.miners then buildings.miners = 0 end
      buildings.miners = buildings.miners + 1

    elseif etype == "transport-belt" then
      belt_count = belt_count + 1

    elseif etype == "inserter" then
      inserter_count = inserter_count + 1

    elseif etype == "electric-pole" then
      power_pole_count = power_pole_count + 1

    elseif etype == "container" or etype == "logistic-container" then
      if not buildings.containers then buildings.containers = 0 end
      buildings.containers = buildings.containers + 1

    elseif etype == "lab" then
      if not buildings.labs then buildings.labs = 0 end
      buildings.labs = buildings.labs + 1

    elseif etype == "generator" or etype == "boiler" or etype == "reactor" then
      if not buildings.power_plants then buildings.power_plants = 0 end
      buildings.power_plants = buildings.power_plants + 1
    end
  end

  -- Add belt/inserter/pole counts to buildings
  if belt_count > 0 then
    buildings.belts_approx = belt_count
  end
  if inserter_count > 0 then
    buildings.inserters = inserter_count
  end
  if power_pole_count > 0 then
    buildings.power_poles = power_pole_count
  end

  -- Simplify resource data: just name + estimated amount
  local resources_simple = {}
  for name, data in pairs(resources) do
    resources_simple[name] = area_query._format_resource_amount(data.estimated_amount)
  end

  return {
    resources = resources_simple,
    resource_count = table_size(resources),
    buildings = buildings,
    building_count = assembler_count + furnace_count + miner_count +
      belt_count + inserter_count + power_pole_count,
  }
end

function area_query._format_resource_amount(amount)
  if amount >= 1000000 then
    return "大量 (~" .. math.floor(amount / 1000000) .. "M)"
  elseif amount >= 10000 then
    return "较多 (~" .. math.floor(amount / 1000) .. "K)"
  elseif amount >= 1000 then
    return "中等 (~" .. math.floor(amount / 1000) .. "K)"
  else
    return "少量 (~" .. math.floor(amount) .. ")"
  end
end

-- ============================================================================
-- Layer 2: Zone Marking & Detailed Query
-- ============================================================================

-- Initialize marks storage
function area_query._ensure_marks()
  if not storage.marks then
    storage.marks = {}
  end
end

function area_query.create_mark(mark_id, corner1, corner2, label)
  area_query._ensure_marks()

  local c1 = utils.table_to_position(corner1)
  local c2 = utils.table_to_position(corner2)

  if not c1 or not c2 then
    return nil, "invalid_corners"
  end

  -- Normalize: c1 = top-left, c2 = bottom-right
  local x1, y1 = math.min(c1.x, c2.x), math.min(c1.y, c2.y)
  local x2, y2 = math.max(c1.x, c2.x), math.max(c1.y, c2.y)

  storage.marks[mark_id] = {
    area = { { x1, y1 }, { x2, y2 } },
    label = label or "",
    created_at = game.tick,
    created_by = "api", -- or "player" when using in-game commands
  }

  utils.info("mark created: " .. mark_id .. " [(" .. x1 .. "," .. y1 .. ")-(" ..
    x2 .. "," .. y2 .. ")]" .. (label and (" '" .. label .. "'") or ""))

  return {
    marked = true,
    mark_id = mark_id,
    area = { x1 = x1, y1 = y1, x2 = x2, y2 = y2 },
  }
end

function area_query.get_mark_detail(mark_id)
  area_query._ensure_marks()

  local mark = storage.marks[mark_id]
  if not mark then
    return nil, "mark_not_found"
  end

  local surface = game.surfaces[1]
  local area = {
    { mark.area[1][1], mark.area[1][2] },
    { mark.area[2][1], mark.area[2][2] },
  }

  local entities = surface.find_entities_filtered { area = area }

  local raw_count = #entities

  -- Compress entities
  local compressed = area_query._compress_entities(entities)

  return {
    mark_id = mark_id,
    label = mark.label,
    area = {
      x1 = mark.area[1][1],
      y1 = mark.area[1][2],
      x2 = mark.area[2][1],
      y2 = mark.area[2][2],
    },
    summary = compressed,
    raw_entity_count = raw_count,
    compressed_entity_count = area_query._count_compressed(compressed),
    created_at_tick = mark.created_at,
  }
end

function area_query.remove_mark(mark_id)
  area_query._ensure_marks()

  if not storage.marks[mark_id] then
    return nil, "mark_not_found"
  end

  storage.marks[mark_id] = nil
  utils.info("mark removed: " .. mark_id)

  return { removed = true, mark_id = mark_id }
end

function area_query.list_marks()
  area_query._ensure_marks()

  local marks = {}
  for id, data in pairs(storage.marks) do
    table.insert(marks, {
      mark_id = id,
      label = data.label,
      area = {
        x1 = data.area[1][1],
        y1 = data.area[1][2],
        x2 = data.area[2][1],
        y2 = data.area[2][2],
      },
      created_at_tick = data.created_at,
      created_by = data.created_by,
    })
  end

  table.sort(marks, function(a, b) return a.created_at_tick > b.created_at_tick end)

  return { marks = marks }
end

-- ============================================================================
-- Entity Compression
-- ============================================================================

function area_query._compress_entities(entities)
  local result = {}

  -- Group entities by compression logic
  local groups = {
    assemblers = {},
    furnaces = {},
    miners = {},
    belts_by_direction = {},
    inserters_by_type = {},
    power_poles_by_type = {},
    containers_by_name = {},
    labs = {},
    resources_by_name = {},
    others = {},
  }

  for _, entity in ipairs(entities) do
    if entity.valid then

    local etype = entity.type

    if etype == "assembling-machine" then
      local recipe = entity.get_recipe()
      local key = recipe and recipe.name or "__no_recipe__"
      if not groups.assemblers[key] then
        groups.assemblers[key] = { recipe = recipe and recipe.name, count = 0, positions = {} }
      end
      groups.assemblers[key].count = groups.assemblers[key].count + 1
      if #groups.assemblers[key].positions < 50 then  -- cap position array
        table.insert(groups.assemblers[key].positions, utils.position_to_table(entity.position))
      end

    elseif etype == "furnace" then
      local recipe = entity.get_recipe()
      local key = entity.name .. "_" .. (recipe and recipe.name or "__no_recipe__")
      if not groups.furnaces[key] then
        groups.furnaces[key] = {
          name = entity.name,
          recipe = recipe and recipe.name,
          count = 0,
          positions = {},
        }
      end
      groups.furnaces[key].count = groups.furnaces[key].count + 1
      if #groups.furnaces[key].positions < 50 then
        table.insert(groups.furnaces[key].positions, utils.position_to_table(entity.position))
      end

    elseif etype == "mining-drill" then
      local key = entity.name
      if not groups.miners[key] then
        groups.miners[key] = { name = entity.name, count = 0, positions = {} }
      end
      groups.miners[key].count = groups.miners[key].count + 1
      if #groups.miners[key].positions < 50 then
        table.insert(groups.miners[key].positions, utils.position_to_table(entity.position))
      end

    elseif etype == "transport-belt" then
      local dir = entity.direction or 0
      local key = entity.name .. "_dir" .. dir
      if not groups.belts_by_direction[key] then
        groups.belts_by_direction[key] = {
          name = entity.name,
          direction = dir,
          count = 0,
          -- Don't store individual positions for belts (too many)
        }
      end
      groups.belts_by_direction[key].count = groups.belts_by_direction[key].count + 1

    elseif etype == "inserter" then
      local key = entity.name
      if not groups.inserters_by_type[key] then
        groups.inserters_by_type[key] = { name = entity.name, count = 0, positions = {} }
      end
      groups.inserters_by_type[key].count = groups.inserters_by_type[key].count + 1
      if #groups.inserters_by_type[key].positions < 30 then
        table.insert(groups.inserters_by_type[key].positions, utils.position_to_table(entity.position))
      end

    elseif etype == "electric-pole" or entity.name:find("pole") then
      local key = entity.name
      if not groups.power_poles_by_type[key] then
        groups.power_poles_by_type[key] = { name = entity.name, count = 0, positions = {} }
      end
      groups.power_poles_by_type[key].count = groups.power_poles_by_type[key].count + 1
      if #groups.power_poles_by_type[key].positions < 20 then
        table.insert(groups.power_poles_by_type[key].positions, utils.position_to_table(entity.position))
      end

    elseif etype == "container" or etype == "logistic-container" then
      local key = entity.name
      if not groups.containers_by_name[key] then
        groups.containers_by_name[key] = { name = entity.name, count = 0, positions = {} }
      end
      groups.containers_by_name[key].count = groups.containers_by_name[key].count + 1
      table.insert(groups.containers_by_name[key].positions, utils.position_to_table(entity.position))

    elseif etype == "lab" then
      if not groups.labs["lab"] then
        groups.labs["lab"] = { count = 0, positions = {} }
      end
      groups.labs["lab"].count = groups.labs["lab"].count + 1
      if #groups.labs["lab"].positions < 20 then
        table.insert(groups.labs["lab"].positions, utils.position_to_table(entity.position))
      end

    elseif etype == "resource" then
      local key = entity.name
      if not groups.resources_by_name[key] then
        groups.resources_by_name[key] = {
          name = entity.name,
          entity_count = 0,
          estimated_amount = 0,
          positions = {},
        }
      end
      groups.resources_by_name[key].entity_count = groups.resources_by_name[key].entity_count + 1
      groups.resources_by_name[key].estimated_amount =
        groups.resources_by_name[key].estimated_amount + (entity.amount or 1000)
      if #groups.resources_by_name[key].positions < 10 then
        table.insert(groups.resources_by_name[key].positions, utils.position_to_table(entity.position))
      end

    else
      -- Misc entities
      local key = entity.name
      if not groups.others[key] then
        groups.others[key] = { name = entity.name, type = etype, count = 0 }
      end
      groups.others[key].count = groups.others[key].count + 1
    end

    end  -- entity.valid
  end

  -- Build result, excluding empty categories
  local function add_if_nonempty(key, group)
    local items = {}
    for _, v in pairs(group) do
      if v.count > 0 then
        table.insert(items, v)
      end
    end
    if #items > 0 then
      result[key] = items
    end
  end

  add_if_nonempty("assemblers", groups.assemblers)
  add_if_nonempty("furnaces", groups.furnaces)
  add_if_nonempty("miners", groups.miners)
  add_if_nonempty("belts", groups.belts_by_direction)
  add_if_nonempty("inserters", groups.inserters_by_type)
  add_if_nonempty("power_poles", groups.power_poles_by_type)
  add_if_nonempty("containers", groups.containers_by_name)
  add_if_nonempty("labs", groups.labs)

  -- Resources: simplify estimated amounts
  if table_size(groups.resources_by_name) > 0 then
    local res = {}
    for _, v in pairs(groups.resources_by_name) do
      table.insert(res, {
        name = v.name,
        estimated = area_query._format_resource_amount(v.estimated_amount),
        entity_count = v.entity_count,
        sample_positions = v.positions,
      })
    end
    result["resources"] = res
  end

  add_if_nonempty("other", groups.others)

  return result
end

function area_query._count_compressed(compressed)
  local count = 0
  for _, category in pairs(compressed) do
    count = count + #category
  end
  return count
end

-- ============================================================================
-- Player Marking Support
-- ============================================================================

function area_query.create_mark_from_player(player_index, mark_id, label)
  local player = game.players[player_index]
  if not player then return nil, "player_not_found" end

  -- Use player's selected area if available
  local area
  if player.selected then
    local e = player.selected
    local pos = e.position
    -- Mark a small area around the selected entity
    area = {
      { pos.x - 5, pos.y - 5 },
      { pos.x + 5, pos.y + 5 },
    }
  else
    -- Use camera position
    local pos = player.position
    area = {
      { pos.x - 20, pos.y - 20 },
      { pos.x + 20, pos.y + 20 },
    }
  end

  storage.marks[mark_id or "player_mark"] = {
    area = area,
    label = label or "Player marked area",
    created_at = game.tick,
    created_by = "player_" .. player_index,
  }

  return { marked = true, mark_id = mark_id }
end

-- Helper to ensure table_size for non-empty chunk counting
function table_size(t)
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count
end

return area_query
