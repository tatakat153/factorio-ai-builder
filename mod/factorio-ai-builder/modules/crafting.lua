--[[
  Factorio AI Builder - Crafting Module
  Unit entities can't use begin_crafting(), so we implement crafting
  by directly removing ingredients and inserting products (instant craft).
--]]

local utils = require("__factorio-ai-builder__/modules/utils")
local agent = require("__factorio-ai-builder__/modules/agent")

local crafting = {}

function crafting.craft_enqueue(recipe_name, count)
  if not agent.exists() then return nil, "no_agent" end
  if storage.agent.emergency_stopped then return nil, "emergency_stopped" end

  local entity = agent.get_entity(); local character = agent.get_character()
  local force = entity.force

  if not force.recipes[recipe_name] or not force.recipes[recipe_name].enabled then
    return nil, "recipe_not_available", { recipe_name = recipe_name }
  end

  local recipe = prototypes.recipe[recipe_name]
  if not recipe then
    return nil, "unknown_recipe", { recipe_name = recipe_name }
  end

  local to_craft = count or 1
  local inv = character.get_main_inventory()
  if not inv then return nil, "no_inventory" end

  -- Check ingredients
  local missing = {}
  for _, ingredient in ipairs(recipe.ingredients) do
    local have = inv.get_item_count(ingredient.name)
    local need = ingredient.amount * to_craft
    if have < need then
      table.insert(missing, {
        name = ingredient.name,
        have = have,
        need = need,
        missing = need - have,
      })
    end
  end

  if #missing > 0 then
    return nil, "missing_ingredients", { recipe = recipe_name, missing = missing }
  end

  -- Remove ingredients
  for _, ingredient in ipairs(recipe.ingredients) do
    inv.remove({ name = ingredient.name, count = ingredient.amount * to_craft })
  end

  -- Insert products
  local products_made = {}
  for _, product in ipairs(recipe.products) do
    local amount = (product.amount or product.amount_min or 1) * to_craft
    local inserted = inv.insert({ name = product.name, count = amount })
    products_made[product.name] = (products_made[product.name] or 0) + (inserted or 0)
  end

  return {
    crafted = true,
    recipe = recipe_name,
    count = to_craft,
    products = products_made,
  }
end

function crafting.cancel_crafting()
  -- Unit entities don't have craft queue, nothing to cancel
  return { cancelled = true, note = "unit entities have no craft queue; crafting is instant" }
end

function crafting.get_queue()
  return { queue = {}, total = 0 }
end

return crafting
