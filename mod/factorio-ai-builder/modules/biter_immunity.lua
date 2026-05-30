--[[
  Factorio AI Builder - Biter Immunity Module
  Prevents the AI character from taking damage from hostile forces.
--]]

local utils = require("__factorio-ai-builder__/modules/utils")
local agent = require("__factorio-ai-builder__/modules/agent")

local biter_immunity = {}

-- Called from control.lua on on_entity_damaged event
function biter_immunity.on_entity_damaged(event)
  if not storage.agent or not storage.agent.entity then return end

  local entity = event.entity
  if not entity or not entity.valid then return end

  -- Only protect our AI agent character
  if entity ~= storage.agent.entity then return end

  -- Check if damage came from an enemy force
  local cause = event.cause
  if cause and cause.valid then
    -- If the attacker is on the "enemy" force, nullify damage
    if cause.force and cause.force.name == "enemy" then
      -- Restore health to max before damage is applied
      local max_hp = entity.health
      pcall(function() max_hp = entity.prototype.max_health end)
      entity.health = max_hp
      utils.debug("Biter attack on agent nullified")
    end

    -- Also protect from enemy projectiles (spitter acid)
    if cause.type == "projectile" then
      if cause.force and cause.force.name == "enemy" then
        local max_hp = entity.health
        pcall(function() max_hp = entity.prototype.max_health end)
        entity.health = max_hp
        utils.debug("Enemy projectile damage nullified")
      end
    end
  end
end

return biter_immunity
