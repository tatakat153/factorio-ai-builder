--[[
  Factorio AI Builder - Placement Module
  Single entity placement with validation (works with unit entity).
--]]

local utils = require("__factorio-ai-builder__/modules/utils")
local agent = require("__factorio-ai-builder__/modules/agent")

local placement = {}

function placement.place_entity(entity_name, position, direction, options)
  if not agent.exists() then return nil, "no_agent" end
  if storage.agent.emergency_stopped then return nil, "emergency_stopped" end

  agent.bring_character_near()

  local unit = agent.get_entity()
  local pos = utils.table_to_position(position)
  if not pos then return nil, "invalid_position" end

  local surface = unit.surface
  local build_dist = agent.get_build_distance()

  -- Check build distance
  local dist = utils.distance({ x = unit.position.x, y = unit.position.y }, pos)
  if dist > build_dist then
    return nil, "too_far", { max_distance = build_dist, actual_distance = dist }
  end

  -- Check if entity prototype exists
  local prototype = prototypes.entity[entity_name]
  if not prototype then return nil, "unknown_entity", { entity_name = entity_name } end

  -- Find the item that places this entity
  local item_name = nil
  local item_count_needed = 1
  if prototype.items_to_place_this and prototype.items_to_place_this[1] then
    item_name = prototype.items_to_place_this[1].name
    item_count_needed = prototype.items_to_place_this[1].count or 1
  end
  if not item_name then item_name = entity_name end

  -- Check inventory
  local inv = unit.get_main_inventory()
  if inv then
    local item_count = inv.get_item_count(item_name)
    if item_count < item_count_needed then
      return nil, "missing_item", { item = item_name, have = item_count, need = item_count_needed }
    end
  end

  -- Check position
  local can_place, reason, existing = utils.can_place_entity(surface, pos, entity_name, unit.force)
  if not can_place then
    return nil, "cannot_place", {
      reason = reason,
      existing_entity = existing and existing.name,
    }
  end

  -- Place entity
  local created = surface.create_entity {
    name = entity_name,
    position = pos,
    direction = direction or 0,
    force = unit.force,
    raise_built = true,
  }

  if not created then return nil, "placement_failed" end

  -- Remove item from inventory
  if inv and item_count_needed > 0 then
    inv.remove({ name = item_name, count = item_count_needed })
  end

  return {
    placed = true,
    entity_name = entity_name,
    unit_number = created.unit_number,
    position = utils.position_to_table(created.position),
  }
end

function placement.pickup_entity(entity_ref, position)
  if not agent.exists() then return nil, "no_agent" end
  if storage.agent.emergency_stopped then return nil, "emergency_stopped" end

  local unit = agent.get_entity()
  local surface = unit.surface
  local entity

  if type(entity_ref) == "number" then
    local found = surface.find_entities_filtered { unit_number = entity_ref, limit = 1 }
    if found and #found > 0 then entity = found[1] end
  else
    local pos = utils.table_to_position(position)
    if pos then entity = utils.get_entity_at(surface, pos, entity_ref) end
  end

  if not entity or not entity.valid then return nil, "entity_not_found" end

  local dist = utils.distance(unit.position, entity.position)
  if dist > agent.get_build_distance() then return nil, "too_far" end
  if entity.name == "ai-builder-agent" then return nil, "cannot_mine_agent" end

  -- Get returned items
  local items_to_return = {}
  if entity.prototype.mineable_properties and entity.prototype.mineable_properties.products then
    for _, product in ipairs(entity.prototype.mineable_properties.products) do
      table.insert(items_to_return, { name = product.name, amount = product.amount or 1 })
    end
  end

  local result = {
    picked_up = true,
    entity_name = entity.name,
    position = utils.position_to_table(entity.position),
    unit_number = entity.unit_number,
    returned_items = items_to_return,
  }

  -- Unit can't use mine_entity, so destroy + insert manually
  entity.destroy()
  for _, item in ipairs(items_to_return) do
    unit.insert(item)
  end

  return result
end

function placement.set_entity_recipe(entity_name, position, recipe_name)
  if not agent.exists() then return nil, "no_agent" end

  local unit = agent.get_entity()
  local pos = utils.table_to_position(position)
  if not pos then return nil, "invalid_position" end

  local surface = unit.surface
  local entities = surface.find_entities_filtered {
    area = { { pos.x - 1, pos.y - 1 }, { pos.x + 1, pos.y + 1 } },
    name = entity_name,
    limit = 1,
  }

  if not entities or #entities == 0 then return nil, "entity_not_found" end
  local target = entities[1]

  local dist = utils.distance(unit.position, target.position)
  if dist > agent.get_build_distance() then return nil, "too_far" end

  if target.set_recipe then
    target.set_recipe(recipe_name)
    return { configured = true, recipe = recipe_name }
  else
    return nil, "entity_no_recipe_support"
  end
end

return placement
