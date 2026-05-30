--[[
  Factorio AI Builder - Inventory Module
  Item transfer between agent and entities.
--]]

local utils = require("__factorio-ai-builder__/modules/utils")
local agent = require("__factorio-ai-builder__/modules/agent")

local inventory = {}

-- ============================================================================
-- Entity Inventory Access
-- ============================================================================

-- Factorio inventory types (defines.inventory):
--   defines.inventory.assembling_machine_input
--   defines.inventory.assembling_machine_output
--   defines.inventory.furnace_source
--   defines.inventory.furnace_result
--   defines.inventory.chest
--   defines.inventory.fuel
--   defines.inventory.item_main -- character main inventory

local INVENTORY_MAP = {
  input = defines.inventory.assembling_machine_input,
  output = defines.inventory.assembling_machine_output,
  furnace_source = defines.inventory.furnace_source,
  furnace_result = defines.inventory.furnace_result,
  fuel = defines.inventory.fuel,
  chest = defines.inventory.chest,
  main = defines.inventory.chest, -- fallback
  ammo = defines.inventory.character_ammo,
  gun = defines.inventory.character_guns,
  trash = defines.inventory.character_trash,
}

function inventory._resolve_inventory_type(inv_type)
  if type(inv_type) == "number" then return inv_type end
  return INVENTORY_MAP[inv_type] or defines.inventory.chest
end

function inventory._get_entity_inventory(entity, inv_type)
  local resolved = inventory._resolve_inventory_type(inv_type)
  local inv = entity.get_inventory(resolved)
  return inv
end

-- ============================================================================
-- Insert Items
-- ============================================================================

function inventory.insert_items(entity_name, position, item_name, count, inv_type)
  if not agent.exists() then
    return nil, "no_agent"
  end

  if storage.agent.emergency_stopped then
    return nil, "emergency_stopped"
  end

  local entity = agent.get_entity(); local character = agent.get_character()
  local pos = utils.table_to_position(position)
  if not pos then
    return nil, "invalid_position"
  end

  local surface = entity.surface

  -- Find target entity
  local entities = surface.find_entities_filtered {
    area = {
      { pos.x - 1, pos.y - 1 },
      { pos.x + 1, pos.y + 1 },
    },
    name = entity_name,
    limit = 1,
  }

  if not entities or #entities == 0 then
    return nil, "entity_not_found"
  end

  local target = entities[1]

  -- Check distance
  local dist = utils.distance(entity.position, target.position)
  if dist > entity.build_distance then
    return nil, "too_far"
  end

  -- Get target inventory
  local target_inv
  if inv_type then
    target_inv = inventory._get_entity_inventory(target, inv_type)
    if not target_inv then
      return nil, "inventory_not_found", { inv_type = inv_type }
    end
  else
    -- Auto-detect: try all available inventories
    for _, def_id in pairs(defines.inventory) do
      local inv = target.get_inventory(def_id)
      if inv and inv.supports_bar() then
        target_inv = inv
        break
      end
    end
    if not target_inv then
      return nil, "no_accessible_inventory"
    end
  end

  -- Check if character has the items
  local char_inv = character.get_main_inventory()
  local have = char_inv.get_item_count(item_name)
  local to_insert = math.min(have, count or have)

  if to_insert <= 0 then
    return nil, "not_enough_items", { item = item_name, have = have, need = count }
  end

  -- Check if target can accept
  local can_insert = target_inv.can_insert({ name = item_name, count = to_insert })
  if not can_insert then
    return nil, "inventory_full_or_incompatible"
  end

  -- Do the transfer
  local inserted = char_inv.remove({ name = item_name, count = to_insert })
  local actually_inserted = target_inv.insert({ name = item_name, count = inserted })

  return {
    inserted = true,
    item = item_name,
    count = actually_inserted,
    target_entity = entity_name,
    target_position = utils.position_to_table(target.position),
  }
end

-- ============================================================================
-- Extract Items
-- ============================================================================

function inventory.extract_items(entity_name, position, item_name, count, inv_type)
  if not agent.exists() then
    return nil, "no_agent"
  end

  if storage.agent.emergency_stopped then
    return nil, "emergency_stopped"
  end

  local entity = agent.get_entity(); local character = agent.get_character()
  local pos = utils.table_to_position(position)
  if not pos then
    return nil, "invalid_position"
  end

  local surface = entity.surface

  local entities = surface.find_entities_filtered {
    area = {
      { pos.x - 1, pos.y - 1 },
      { pos.x + 1, pos.y + 1 },
    },
    name = entity_name,
    limit = 1,
  }

  if not entities or #entities == 0 then
    return nil, "entity_not_found"
  end

  local target = entities[1]
  local dist = utils.distance(entity.position, target.position)
  if dist > entity.build_distance then
    return nil, "too_far"
  end

  -- Get target inventory
  local target_inv
  if inv_type then
    target_inv = inventory._get_entity_inventory(target, inv_type)
  else
    for _, def_id in pairs(defines.inventory) do
      local inv = target.get_inventory(def_id)
      if inv and inv.supports_bar() then
        target_inv = inv
        break
      end
    end
  end

  if not target_inv then
    return nil, "no_accessible_inventory"
  end

  -- Check if target has the items
  local have = target_inv.get_item_count(item_name)
  local to_extract = math.min(have, count or have)

  if to_extract <= 0 then
    return nil, "not_enough_items", { item = item_name, have = have, need = count }
  end

  -- Check if character can accept
  local char_inv = character.get_main_inventory()
  local can_insert = char_inv.can_insert({ name = item_name, count = to_extract })
  if not can_insert then
    return nil, "agent_inventory_full"
  end

  -- Do the transfer
  local extracted = target_inv.remove({ name = item_name, count = to_extract })
  char_inv.insert({ name = item_name, count = extracted })

  return {
    extracted = true,
    item = item_name,
    count = extracted,
    source_entity = entity_name,
    source_position = utils.position_to_table(target.position),
  }
end

return inventory
