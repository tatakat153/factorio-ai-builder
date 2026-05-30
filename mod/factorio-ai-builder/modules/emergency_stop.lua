--[[
  Factorio AI Builder - Emergency Stop Module
  Kill switch: cancel all pending operations, stop character movement.
--]]

local utils = require("__factorio-ai-builder__/modules/utils")
local agent = require("__factorio-ai-builder__/modules/agent")

local emergency_stop = {}

function emergency_stop.trigger()
  if not agent.exists() then
    return nil, "no_agent"
  end

  local entity = agent.get_entity()
  local cancelled = {}

  -- 1. Stop movement
  if storage.agent.walk_state and storage.agent.walk_state.state ~= "arrived" then
    entity.commandable.set_command({ type = defines.command.stop })
    storage.agent.walk_state = nil
    table.insert(cancelled, "movement")
  end

  -- 2. Cancel all batch builds
  if storage.batches then
    for batch_id, batch in pairs(storage.batches) do
      if batch.state == "building" or batch.state == "queued" then
        batch.state = "cancelled"
        table.insert(cancelled, "batch_" .. batch_id)
      end
    end
  end

  -- 3. Cancel hand crafting
  local crafting_queue = entity.crafting_queue
  if #crafting_queue > 0 then
    entity.cancel_crafting { count = #crafting_queue }
    table.insert(cancelled, "crafting")
  end

  -- 4. Clear current action
  agent.clear_current_action()

  -- 5. Clear pending actions
  storage.agent.pending_actions = {}

  -- 6. Set emergency flag
  storage.agent.emergency_stopped = true

  utils.info("EMERGENCY STOP triggered - cancelled: " .. table.concat(cancelled, ", "))

  return {
    stopped = true,
    cancelled_actions = cancelled,
  }
end

function emergency_stop.reset()
  if not agent.exists() then
    return nil, "no_agent"
  end

  if not storage.agent.emergency_stopped then
    return nil, "not_emergency_stopped"
  end

  storage.agent.emergency_stopped = false
  utils.info("Emergency stop reset - agent can receive commands again")

  return { reset = true }
end

function emergency_stop.is_stopped()
  return storage.agent and storage.agent.emergency_stopped
end

return emergency_stop
