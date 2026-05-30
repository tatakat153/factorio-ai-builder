--[[
  Factorio AI Builder - Remote Interface
  All external-facing functions exposed via Factorio's remote.call() system.

  Usage from RCON:
    /c remote.call("ai_builder", "create_agent", {x=0, y=0})
    /c remote.call("ai_builder", "walk_to", {x=100, y=200})
    /c remote.call("ai_builder", "get_overview", {x=100, y=100}, 3)

  All functions return tables (serializable via our JSON encoder).
  Bridge service converts these to JSON for HTTP responses.
--]]

local utils = require("__factorio-ai-builder__/modules/utils")
local agent_mod = require("__factorio-ai-builder__/modules/agent")
local movement = require("__factorio-ai-builder__/modules/movement")
local placement = require("__factorio-ai-builder__/modules/placement")
local mining = require("__factorio-ai-builder__/modules/mining")
local inventory = require("__factorio-ai-builder__/modules/inventory")
local crafting = require("__factorio-ai-builder__/modules/crafting")
local research = require("__factorio-ai-builder__/modules/research")
local area_query = require("__factorio-ai-builder__/modules/area_query")
local batch_builder = require("__factorio-ai-builder__/modules/batch_builder")
local emergency_stop = require("__factorio-ai-builder__/modules/emergency_stop")
local templates = require("__factorio-ai-builder__/templates/default")

-- ============================================================================
-- Response helpers
-- ============================================================================

local function ok(data)
  return { success = true, data = data }
end

local function err(code, detail)
  return { success = false, error = code, detail = detail }
end

local function wrap(func)
  return function(...)
    local ok_result, data1, data2 = pcall(func, ...)
    if not ok_result then
      return err("internal_error", tostring(data1))
    end
    if data1 == nil and data2 then
      -- Function returned (nil, error_code, error_detail)
      return err(data2, nil)
    end
    return ok(data1)
  end
end

-- ============================================================================
-- Remote Interface Registration
-- ============================================================================

local interface = {}

-- === Agent ===
interface.create_agent = wrap(function(position)
  return agent_mod.create(position)
end)

interface.destroy_agent = wrap(function()
  return agent_mod.destroy()
end)

interface.get_agent_state = wrap(function()
  return agent_mod.get_state()
end)

interface.give_items = wrap(function(item_name, count)
  if not agent_mod.exists() then return nil, "no_agent" end
  local character = agent_mod.get_character()
  if not character or not character.valid then return nil, "no_character" end
  local count = count or 1
  local inserted = character.insert({ name = item_name, count = count })
  return { given = true, item = item_name, count = inserted }
end)

interface.get_inventory = wrap(function()
  return agent_mod.get_inventory()
end)

-- === Movement ===
interface.walk_to = wrap(function(goal, strict_goal)
  return movement.walk_to(goal, strict_goal)
end)

interface.approach_to = wrap(function(target, distance)
  return movement.approach_to(target, distance)
end)

interface.stop_moving = wrap(function()
  return movement.stop()
end)

interface.get_movement_status = wrap(function()
  return movement.get_status()
end)

interface.get_obstacles_near = wrap(function(radius)
  return movement.get_obstacles_near(radius)
end)

-- === Placement ===
interface.place_entity = wrap(function(entity_name, position, direction, options)
  return placement.place_entity(entity_name, position, direction, options)
end)

interface.pickup_entity = wrap(function(entity_ref, position)
  return placement.pickup_entity(entity_ref, position)
end)

interface.set_entity_recipe = wrap(function(entity_name, position, recipe_name)
  return placement.set_entity_recipe(entity_name, position, recipe_name)
end)

-- === Mining ===
interface.mine_resource = wrap(function(resource_name, max_count, position_hint)
  return mining.mine_resource(resource_name, max_count, position_hint)
end)

-- === Inventory ===
interface.insert_items = wrap(function(entity_name, position, item_name, count, inv_type)
  return inventory.insert_items(entity_name, position, item_name, count, inv_type)
end)

interface.extract_items = wrap(function(entity_name, position, item_name, count, inv_type)
  return inventory.extract_items(entity_name, position, item_name, count, inv_type)
end)

-- === Crafting ===
interface.craft_enqueue = wrap(function(recipe_name, count)
  return crafting.craft_enqueue(recipe_name, count)
end)

interface.cancel_crafting = wrap(function(recipe_name, count)
  return crafting.cancel_crafting(recipe_name, count)
end)

interface.get_crafting_queue = wrap(function()
  return crafting.get_queue()
end)

-- === Research ===
interface.get_technologies = wrap(function(only_available)
  return research.get_technologies(only_available)
end)

interface.enqueue_research = wrap(function(technology_name)
  return research.enqueue_research(technology_name)
end)

interface.cancel_research = wrap(function()
  return research.cancel_current_research()
end)

interface.get_current_research = wrap(function()
  return research.get_current_research()
end)

-- === Area Query ===
interface.get_overview = wrap(function(center, radius_chunks)
  return area_query.get_overview(center, radius_chunks)
end)

interface.create_mark = wrap(function(mark_id, corner1, corner2, label)
  return area_query.create_mark(mark_id, corner1, corner2, label)
end)

interface.get_mark_detail = wrap(function(mark_id)
  return area_query.get_mark_detail(mark_id)
end)

interface.remove_mark = wrap(function(mark_id)
  return area_query.remove_mark(mark_id)
end)

interface.list_marks = wrap(function()
  return area_query.list_marks()
end)

-- === Batch Builder ===
interface.batch_build = wrap(function(template_name, anchor, count, options)
  return batch_builder.build(template_name, anchor, count, options)
end)

interface.get_batch_status = wrap(function(batch_id)
  return batch_builder.get_batch_status(batch_id)
end)

interface.resume_batch = wrap(function(batch_id, resolution)
  return batch_builder.resume(batch_id, resolution)
end)

interface.cancel_batch = wrap(function(batch_id)
  return batch_builder.cancel(batch_id)
end)

-- === Emergency ===
interface.emergency_stop = wrap(function()
  return emergency_stop.trigger()
end)

interface.reset_emergency = wrap(function()
  return emergency_stop.reset()
end)

-- === Templates ===
interface.list_templates = wrap(function()
  return templates.list_with_descriptions()
end)

-- === Recipes (convenience) ===
interface.get_recipes = wrap(function()
  return agent_mod.get_available_recipes()
end)

-- ============================================================================
-- Register with Factorio
-- ============================================================================

-- Helper to get interface keys
local function get_interface_keys(t)
  local keys = {}
  for k, v in pairs(t) do
    if type(v) == "function" then
      table.insert(keys, k)
    end
  end
  table.sort(keys)
  return keys
end

local function table_concat_safe(t, sep)
  if #t == 0 then return "(none)" end
  return table.concat(t, sep or ", ")
end

remote.add_interface("ai_builder", interface)

-- Also expose for debugging: direct print of interface methods
utils.info("AI Builder remote interface registered: " ..
  table_concat_safe(get_interface_keys(interface), ", "))
