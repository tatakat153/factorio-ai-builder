--[[
  Factorio AI Builder - Agent Module
  Hybrid: visible unit entity (native pathfinding) + hidden character entity (inventory/crafting).
--]]

local config = require("__factorio-ai-builder__/config")
local utils = require("__factorio-ai-builder__/modules/utils")

local agent = {}

-- ============================================================================
-- Entity Access
-- ============================================================================

function agent.get_entity()
  return storage.agent and storage.agent.entity
end

function agent.get_character()
  return storage.agent and storage.agent.character
end

function agent.exists()
  local e = agent.get_entity()
  return e ~= nil and e.valid
end

-- ============================================================================
-- Create / Destroy
-- ============================================================================

function agent.create(position)
  if agent.exists() then return nil, "agent_already_exists" end

  local surface = game.surfaces[1]
  local pos = position or { x = 0, y = 0 }

  local entity = surface.create_entity {
    name = config.AGENT_ENTITY_NAME, position = pos, force = config.AGENT_FORCE_NAME,
  }
  if not entity then return nil, "create_failed" end

  local character = surface.create_entity {
    name = "character", position = { x = -10000, y = -10000 }, force = config.AGENT_FORCE_NAME,
  }

  storage.agent = {
    entity = entity, character = character,
    created_at = game.tick, emergency_stopped = false,
    pending_actions = {}, current_action = nil,
  }

  agent._update_chart_tag(entity)
  utils.info("Agent created at " .. pos.x .. "," .. pos.y)
  return entity
end

function agent.destroy()
  if not agent.exists() then return false, "no_agent" end
  for _, a in pairs(storage.agent.pending_actions) do if a.on_cancel then a.on_cancel() end end
  storage.agent.pending_actions = {}; storage.agent.current_action = nil
  agent._remove_chart_tag()
  if storage.agent.character and storage.agent.character.valid then storage.agent.character.destroy() end
  agent.get_entity().destroy()
  storage.agent = nil
  utils.info("Agent destroyed")
  return true
end

function agent.get_position()
  if not agent.exists() then return nil end
  return utils.position_to_table(agent.get_entity().position)
end

-- ============================================================================
-- State
-- ============================================================================

function agent.get_state()
  if not agent.exists() then return { exists = false } end

  local entity = agent.get_entity()
  local character = agent.get_character()
  local inv = character and character.valid and character.get_main_inventory()
  local items = {}
  if inv then
    local c = inv.get_contents(); local s = {}
    for n, cnt in pairs(c) do
      local actual_count = type(cnt) == "table" and (cnt.count or 0) or cnt
      table.insert(s, { name = n, count = actual_count })
    end
    table.sort(s, function(a, b) return a.count > b.count end)
    for i = 1, math.min(#s, config.INVENTORY_MAX_SUMMARY_ITEMS) do items[i] = s[i] end
  end

  return {
    exists = true,
    position = utils.position_to_table(entity.position),
    surface = entity.surface.name,
    health = entity.health, max_health = entity.health,
    emergency_stopped = storage.agent.emergency_stopped,
    inventory = items,
    inventory_total_items = inv and inv.get_item_count() or 0,
    is_moving = storage.agent.walk_state and storage.agent.walk_state.state == "walking",
    current_action = storage.agent.current_action,
    pending_action_count = #storage.agent.pending_actions,
  }
end

function agent.get_inventory()
  if not agent.exists() then return nil end
  local c = agent.get_character()
  if not c or not c.valid then return {} end
  local inv = c.get_main_inventory()
  return inv and inv.get_contents() or {}
end

function agent.is_busy()
  return storage.agent and (storage.agent.current_action ~= nil or #storage.agent.pending_actions > 0)
end

function agent.set_current_action(t, d)
  storage.agent.current_action = { type = t, data = d, started_at = game.tick }
end

function agent.clear_current_action()
  storage.agent.current_action = nil
end

function agent.get_build_distance() return 10 end

-- Teleport character to unit position for operations that need proximity
function agent.bring_character_near()
  if not agent.exists() then return end
  local c = agent.get_character()
  local u = agent.get_entity()
  if c and c.valid and u and u.valid and utils.distance(c.position, u.position) > 15 then
    c.teleport(u.position)
  end
end

function agent.send_character_away()
  if not agent.exists() then return end
  local c = agent.get_character()
  if c and c.valid then
    c.teleport(-10000, -10000)
  end
end

-- ============================================================================
-- Recipes
-- ============================================================================

function agent.get_available_recipes()
  if not agent.exists() then return {} end
  local force = agent.get_entity().force
  local recipes = {}
  for name, recipe in pairs(prototypes.recipe) do
    if force.recipes[name] and force.recipes[name].enabled then
      local ings, prods = {}, {}
      for _, ing in ipairs(recipe.ingredients) do
        table.insert(ings, { name = ing.name, amount = ing.amount, type = ing.type or "item" })
      end
      for _, prod in ipairs(recipe.products) do
        table.insert(prods, { name = prod.name, amount = prod.amount or prod.amount_min or 1, type = prod.type or "item" })
      end
      table.insert(recipes, { name = name, ingredients = ings, products = prods, category = recipe.category or "crafting" })
    end
  end
  table.sort(recipes, function(a, b) return a.name < b.name end)
  return recipes
end

-- ============================================================================
-- Map Marker
-- ============================================================================

function agent._update_chart_tag(entity)
  if not entity or not entity.valid then return end
  agent._remove_chart_tag()
  local tag = entity.force.add_chart_tag(entity.surface, {
    position = entity.position, icon = { type = "virtual", name = "signal-dot" }, text = "AI 助手",
  })
  if tag then storage.agent.chart_tag = tag end
end

function agent._remove_chart_tag()
  if storage.agent and storage.agent.chart_tag then
    if storage.agent.chart_tag.valid then storage.agent.chart_tag.destroy() end
    storage.agent.chart_tag = nil
  end
end

function agent.update_chart_tag()
  if not agent.exists() then return end
  local entity = agent.get_entity()
  if storage.agent.chart_tag and storage.agent.chart_tag.valid then
    storage.agent.chart_tag.position = entity.position
  else
    agent._update_chart_tag(entity)
  end
  -- Keep character offset from unit (2 tiles to avoid collision, within build range)
  local c = agent.get_character()
  if c and c.valid then
    c.teleport({ x = entity.position.x + 2, y = entity.position.y })
  end
end

return agent
