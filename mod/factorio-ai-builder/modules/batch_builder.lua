--[[
  Factorio AI Builder - Batch Builder Module
  Template-based repetitive construction with obstacle detection.

  Flow:
  1. Bridge calls batch_build(template, anchor, count, options)
  2. Template is expanded to absolute coordinates
  3. Pre-check phase: scan all positions for obstacles and missing items
  4. Build phase (on_tick): place entities in build_order sequence
  5. On obstacle/inventory issue: pause, report to AI via status
  6. AI calls resume with resolution: skip / destroy / adjust
--]]

local config = require("__factorio-ai-builder__/config")
local utils = require("__factorio-ai-builder__/modules/utils")
local agent = require("__factorio-ai-builder__/modules/agent")

-- Load templates
local templates = require("__factorio-ai-builder__/templates/default")

local batch_builder = {}

-- ============================================================================
-- Batch State Structure
-- ============================================================================

-- storage.batches[batch_id] = {
--   template_name: string,
--   anchor: {x, y},
--   count: number,
--   options: table,
--   state: "queued" | "building" | "paused_obstacle" | "paused_missing" | "completed" | "cancelled",
--   entities: {{name, position, direction}, ...}  -- all entities to place
--   current_index: number,
--   obstacles: {{position, entity_name}, ...},
--   missing_items: {{name, have, need}, ...},
--   progress: {built: number, total: number},
--   created_at: number,
-- }

-- ============================================================================
-- Public API
-- ============================================================================

function batch_builder.build(template_name, anchor, count, options)
  if not agent.exists() then
    return nil, "no_agent"
  end

  if storage.agent.emergency_stopped then
    return nil, "emergency_stopped"
  end

  local template = templates.get(template_name)
  if not template then
    return nil, "unknown_template", { template_name = template_name, available = templates.list() }
  end

  local anchor_pos = utils.table_to_position(anchor)
  if not anchor_pos then
    return nil, "invalid_anchor"
  end

  local n = count or 1
  if n < 1 then n = 1 end

  -- Generate all entity placement positions
  local entities = batch_builder._expand_template(template, anchor_pos, n)
  if not entities or #entities == 0 then
    return nil, "template_expansion_failed"
  end

  -- Validate: check all entities are placeable (scout phase)
  local obstacles = {}
  local missing_items = {}
  local entity = agent.get_entity()
  local surface = entity.surface
  local inv = entity.get_main_inventory()

  for _, entity_def in ipairs(entities) do
    -- Check if position is blocked
    local can_place, reason, existing = utils.can_place_entity(
      surface, entity_def.position, entity_def.name, entity.force
    )
    if not can_place then
      table.insert(obstacles, {
        position = entity_def.position,
        entity_name = entity_def.name,
        reason = reason,
        existing = existing and existing.name,
      })
    end

    -- Check if we have the item
    local prototype = prototypes.entity[entity_def.name]
    if prototype and prototype.items_to_place_this and prototype.items_to_place_this[1] then
      local item_name = prototype.items_to_place_this[1].name
      local item_count_needed = prototype.items_to_place_this[1].count or 1

      -- Accumulate needed items
      local found = false
      for _, mi in ipairs(missing_items) do
        if mi.name == item_name then
          mi.need = mi.need + item_count_needed
          found = true
          break
        end
      end
      if not found then
        table.insert(missing_items, {
          name = item_name,
          need = item_count_needed,
        })
      end
    end
  end

  -- Check inventory against needed items
  local real_missing = {}
  for _, mi in ipairs(missing_items) do
    local have = inv and inv.get_item_count(mi.name) or 0
    if have < mi.need then
      mi.have = have
      table.insert(real_missing, mi)
    end
  end

  -- Generate batch ID
  local batch_id = "batch_" .. game.tick .. "_" .. math.random(1000, 9999)

  -- Initialize batch state
  if not storage.batches then storage.batches = {} end

  -- Filter out obstacles if skip_obstacles was pre-requested
  local skip_positions = {}
  if options and options.obstacle_resolution == "skip" then
    for _, obs in ipairs(obstacles) do
      skip_positions[obs.position.x .. "," .. obs.position.y] = true
    end
    obstacles = {}
  end

  -- Remove entities at obstacle positions from the build list
  local filtered_entities = {}
  for _, ent in ipairs(entities) do
    if not skip_positions[ent.position.x .. "," .. ent.position.y] then
      table.insert(filtered_entities, ent)
    end
  end

  storage.batches[batch_id] = {
    template_name = template_name,
    anchor = anchor_pos,
    count = n,
    options = options or {},
    state = "queued",
    entities = filtered_entities,
    current_index = 1,
    obstacles = obstacles,
    missing_items = real_missing,
    progress = { built = 0, total = #filtered_entities },
    created_at = game.tick,
    character_position_at_start = utils.position_to_table(entity.position),
  }

  -- If obstacles found and not skipped, pause immediately
  if #obstacles > 0 and not skip_positions then
    storage.batches[batch_id].state = "paused_obstacle"
    utils.info("batch " .. batch_id .. ": paused - " .. #obstacles ..
      " obstacles at start (total entities: " .. #filtered_entities .. ")")
    return {
      queued = true,
      batch_id = batch_id,
      state = "paused_obstacle",
      obstacles = obstacles,
      progress = storage.batches[batch_id].progress,
    }
  end

  -- If missing items, pause
  if #real_missing > 0 then
    storage.batches[batch_id].state = "paused_missing"
    utils.info("batch " .. batch_id .. ": paused - " .. #real_missing ..
      " items missing, " .. #filtered_entities .. " entities queued")
    return {
      queued = true,
      batch_id = batch_id,
      state = "paused_missing",
      missing_items = real_missing,
      progress = storage.batches[batch_id].progress,
    }
  end

  -- Start building
  storage.batches[batch_id].state = "building"
  agent.set_current_action("batch_building", { batch_id = batch_id })

  utils.info("batch " .. batch_id .. ": building " .. #filtered_entities ..
    " entities for template '" .. template_name .. "'")

  return {
    queued = true,
    batch_id = batch_id,
    state = "building",
    progress = { built = 0, total = #filtered_entities },
    estimated_ticks = math.ceil(#filtered_entities / config.BATCH_PLACEMENTS_PER_TICK),
  }
end

function batch_builder.get_batch_status(batch_id)
  if not storage.batches or not storage.batches[batch_id] then
    return nil, "batch_not_found"
  end

  local batch = storage.batches[batch_id]

  return {
    batch_id = batch_id,
    template_name = batch.template_name,
    state = batch.state,
    progress = batch.progress,
    obstacles = batch.obstacles,
    missing_items = batch.missing_items,
    created_at = batch.created_at,
  }
end

function batch_builder.resume(batch_id, resolution)
  if not storage.batches or not storage.batches[batch_id] then
    return nil, "batch_not_found"
  end

  local batch = storage.batches[batch_id]

  if batch.state == "completed" then
    return nil, "already_completed"
  end

  if batch.state == "cancelled" then
    return nil, "batch_cancelled"
  end

  if resolution == "skip_obstacles" then
    -- Filter out entities at obstacle positions
    local skip_positions = {}
    for _, obs in ipairs(batch.obstacles) do
      skip_positions[obs.position.x .. "," .. obs.position.y] = true
    end

    local filtered = {}
    for _, ent in ipairs(batch.entities) do
      if not skip_positions[ent.position.x .. "," .. ent.position.y] then
        table.insert(filtered, ent)
      end
    end

    batch.entities = filtered
    batch.obstacles = {}
    batch.current_index = 1
    batch.progress = { built = 0, total = #filtered }
    batch.state = "building"
    utils.info("batch " .. batch_id .. ": resumed (skipping " ..
      table_size(skip_positions) .. " obstacles)")

  elseif resolution == "destroy_obstacles" then
    -- Destroy obstacle entities, then resume
    local entity = agent.get_entity()
    local surface = entity.surface

    for _, obs in ipairs(batch.obstacles) do
      local entities = surface.find_entities_filtered {
        position = obs.position,
        limit = 1,
      }
      if entities and #entities > 0 and entities[1].valid then
        -- Don't destroy other characters
        if entities[1].name ~= "character" then
          entities[1].destroy()
        end
      end
    end

    batch.obstacles = {}
    batch.state = "building"
    utils.info("batch " .. batch_id .. ": resumed (destroyed obstacles)")

  elseif resolution == "force_continue" then
    -- Just continue building where we left off, ignoring obstacles
    batch.state = "building"
    utils.info("batch " .. batch_id .. ": resumed (force continue)")

  elseif resolution == "cancel" then
    return batch_builder.cancel(batch_id)

  else
    return nil, "unknown_resolution", { valid = { "skip_obstacles", "destroy_obstacles", "force_continue", "cancel" } }
  end

  return {
    resumed = true,
    batch_id = batch_id,
    state = batch.state,
    progress = batch.progress,
  }
end

function batch_builder.cancel(batch_id)
  if not storage.batches or not storage.batches[batch_id] then
    return nil, "batch_not_found"
  end

  storage.batches[batch_id].state = "cancelled"
  utils.info("batch " .. batch_id .. ": cancelled")

  if storage.agent.current_action and
     storage.agent.current_action.type == "batch_building" and
     storage.agent.current_action.data.batch_id == batch_id then
    agent.clear_current_action()
  end

  return { cancelled = true, batch_id = batch_id }
end

-- ============================================================================
-- on_tick Handler (called from control.lua)
-- ============================================================================

function batch_builder.on_tick()
  if not storage.batches then return end
  if not agent.exists() then return end

  local entity = agent.get_entity()
  local surface = entity.surface
  local inv = entity.get_main_inventory()

  -- First pass: collect all building batches
  local building_batches = {}
  for batch_id, batch in pairs(storage.batches) do
    if batch.state == "building" and batch.current_index <= #batch.entities then
      table.insert(building_batches, { id = batch_id, batch = batch })
    end
  end

  if #building_batches == 0 then return end

  -- Process round-robin to be fair across batches
  local placements_this_tick = 0
  local max_placements = config.BATCH_PLACEMENTS_PER_TICK

  for _, entry in ipairs(building_batches) do
    if placements_this_tick >= max_placements then break end

    local batch = entry.batch
    local batch_id = entry.id

    -- Place up to remaining quota for this tick
    local remaining = max_placements - placements_this_tick
    local placed = 0

    for i = 1, remaining do
      if batch.current_index > #batch.entities then
        batch.state = "completed"
        utils.info("batch " .. batch_id .. ": completed - " ..
          batch.progress.built .. " entities placed")
        break
      end

      local ent_def = batch.entities[batch.current_index]
      local should_skip = false

      -- Check distance (entity must be near the build site)
      local dist = utils.distance(entity.position, ent_def.position)
      local build_limit = agent.get_build_distance()
      if dist > build_limit * 1.5 then
        -- Too far, can't build. Skip for now, return later.
        should_skip = true
      end

      if not should_skip then
        -- Check if position is still clear (may have changed)
        local can_place, reason, existing = utils.can_place_entity(
          surface, ent_def.position, ent_def.name, entity.force
        )
        if not can_place then
          -- New obstacle: pause and report
          table.insert(batch.obstacles, {
            position = ent_def.position,
            entity_name = ent_def.name,
            reason = reason,
            existing = existing and existing.name,
          })
          batch.state = "paused_obstacle"
          utils.info("batch " .. batch_id .. ": paused - new obstacle at " ..
            ent_def.position.x .. "," .. ent_def.position.y)
          break  -- stop this batch's loop, resume after AI decision
        end
      end

      if not should_skip then
        -- Check inventory for the needed item
        local prototype = prototypes.entity[ent_def.name]
        if prototype and prototype.items_to_place_this and prototype.items_to_place_this[1] then
          local item_name = prototype.items_to_place_this[1].name
          local count_needed = prototype.items_to_place_this[1].count or 1
          local have = inv and inv.get_item_count(item_name) or 0
          if have < count_needed then
            -- Missing items
            batch.missing_items = batch.missing_items or {}
            local found = false
            for _, mi in ipairs(batch.missing_items) do
              if mi.name == item_name then
                mi.need = mi.need + (count_needed * (#batch.entities - batch.current_index + 1))
                found = true
                break
              end
            end
            if not found then
              table.insert(batch.missing_items, {
                name = item_name,
                have = have,
                need = count_needed,
              })
            end
            batch.state = "paused_missing"
            utils.info("batch " .. batch_id .. ": paused - missing " ..
              item_name .. " (have: " .. have .. ", need: " .. count_needed .. ")")
            break  -- stop this batch's loop, resume after AI decision
          end

          -- Remove item from inventory
          inv.remove({ name = item_name, count = count_needed })
        end
      end

      if not should_skip then
        -- Place the entity
        local created = surface.create_entity {
          name = ent_def.name,
          position = ent_def.position,
          direction = ent_def.direction or 0,
          force = entity.force,
          raise_built = true,
        }

        if created then
          placed = placed + 1
          batch.progress.built = batch.progress.built + 1
        end
      end

      -- Always advance the index (skip or placed)
      batch.current_index = batch.current_index + 1
    end

    placements_this_tick = placements_this_tick + placed

    -- Check completion
  end
end

-- ============================================================================
-- Template Expansion
-- ============================================================================

function batch_builder._expand_template(template, anchor, count)
  local entities = {}
  local build_order = template.build_order or {}
  local sorted_offsets = {}

  -- Sort offsets by build_order for proper construction sequence
  if #build_order > 0 then
    -- build_order contains indices into template.entities (1-based)
    for _, idx in ipairs(build_order) do
      if idx >= 1 and idx <= #template.entities then
        sorted_offsets[#sorted_offsets + 1] = template.entities[idx]
      end
    end
    -- Add any entities not in build_order at the end
    local seen = {}
    for _, idx in ipairs(build_order) do seen[idx] = true end
    for i, entity in ipairs(template.entities) do
      if not seen[i] then
        sorted_offsets[#sorted_offsets + 1] = entity
      end
    end
  else
    sorted_offsets = template.entities
  end

  local repeat_x = template.repeat_x or 0
  local repeat_y = template.repeat_y or 0

  -- For 1D repeat (e.g., smelter row), count is the horizontal repeat count
  -- For 2D repeat, we'd use a grid approach (simplified for now)
  for i = 1, count do
    local offset_x = (i - 1) * repeat_x
    local offset_y = (i - 1) * repeat_y

    for _, entity_def in ipairs(sorted_offsets) do
      local pos = {
        x = anchor.x + entity_def.offset[1] + offset_x,
        y = anchor.y + entity_def.offset[2] + offset_y,
      }

      table.insert(entities, {
        name = entity_def.name,
        position = pos,
        direction = entity_def.direction or 0,
      })
    end
  end

  return entities
end

return batch_builder
