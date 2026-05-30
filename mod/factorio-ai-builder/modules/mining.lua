--[[
  Factorio AI Builder - Mining Module
  Resource mining for unit entity (uses destroy + manual inventory insert).
--]]

local utils = require("__factorio-ai-builder__/modules/utils")
local agent = require("__factorio-ai-builder__/modules/agent")

local mining = {}

function mining.mine_resource(resource_name, max_count, position_hint)
  if not agent.exists() then
    return nil, "no_agent"
  end

  if storage.agent.emergency_stopped then
    return nil, "emergency_stopped"
  end

  agent.bring_character_near()

  local entity = agent.get_entity(); local character = agent.get_character()
  local surface = entity.surface

  -- Find nearest resource entity of the given type
  local center = position_hint and utils.table_to_position(position_hint) or entity.position
  local max_distance = 50

  local entities = surface.find_entities_filtered {
    area = {
      { center.x - max_distance, center.y - max_distance },
      { center.x + max_distance, center.y + max_distance },
    },
    name = resource_name,
    limit = 50,
  }

  if not entities or #entities == 0 then
    return nil, "no_resource_found", { resource_name = resource_name, near = center }
  end

  -- Sort by distance
  local epos = entity.position
  table.sort(entities, function(a, b)
    return utils.distance(epos, a.position) < utils.distance(epos, b.position)
  end)

  -- Check distance
  local nearest = entities[1]
  local dist = utils.distance(epos, nearest.position)
  local build_dist = agent.get_build_distance()

  if dist > build_dist then
    return nil, "resource_too_far", {
      nearest_position = utils.position_to_table(nearest.position),
      distance = dist,
      max_reach = build_dist,
    }
  end

  -- Mine resources using character (only character can mine_entity)
  local mined = 0
  local target_count = max_count or math.huge
  local results = {}
  local character = agent.get_character()

  for _, res_entity in ipairs(entities) do
    if mined >= target_count then break end
    if res_entity.valid and character and character.valid then
      -- Use character.mine_entity to properly get items
      if character.can_mine_entity(res_entity) then
        -- Get expected products before mining
        local products = res_entity.prototype.mineable_properties and
          res_entity.prototype.mineable_properties.products
        local expected = {}
        if products then
          for _, prod in ipairs(products) do
            expected[prod.name] = (expected[prod.name] or 0) + (prod.amount or 1)
          end
        end

        -- Actually mine (items go to character inventory automatically)
        character.mine_entity(res_entity, true)

        -- Track results
        for name, amount in pairs(expected) do
          local actual = math.min(amount, target_count - mined)
          if actual > 0 then
            results[name] = (results[name] or 0) + actual
            mined = mined + actual
          end
        end
      else
        -- Fallback: destroy + manual insert
        local products = res_entity.prototype.mineable_properties and
          res_entity.prototype.mineable_properties.products
        local to_insert = {}
        if products then
          for _, prod in ipairs(products) do
            to_insert[prod.name] = (to_insert[prod.name] or 0) + (prod.amount or 1)
          end
        end
        res_entity.destroy()
        for item_name, item_amount in pairs(to_insert) do
          local actual = math.min(item_amount, target_count - mined)
          if actual > 0 then
            character.insert({ name = item_name, count = actual })
            results[item_name] = (results[item_name] or 0) + actual
            mined = mined + actual
          end
        end
      end
    end
  end

  return {
    mined = true,
    counts = results,
    total_mined = mined,
    target = max_count,
    reached_target = mined >= target_count,
  }
end

return mining
