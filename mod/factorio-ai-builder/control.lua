--[[
  Factorio AI Builder - Control (Entry Point)
  Event registration, on_tick dispatch, chat commands.
--]]

local config = require("__factorio-ai-builder__/config")
local utils = require("__factorio-ai-builder__/modules/utils")
local agent_mod = require("__factorio-ai-builder__/modules/agent")
local movement = require("__factorio-ai-builder__/modules/movement")
local batch_builder = require("__factorio-ai-builder__/modules/batch_builder")
local biter_immunity = require("__factorio-ai-builder__/modules/biter_immunity")
local emergency_stop = require("__factorio-ai-builder__/modules/emergency_stop")
local templates = require("__factorio-ai-builder__/templates/default")
local area_query = require("__factorio-ai-builder__/modules/area_query")

-- Load remote interface (registers with Factorio's remote system)
require("__factorio-ai-builder__/remote_interface")

-- ============================================================================
-- Lifecycle Events
-- ============================================================================

script.on_init(function()
  utils.info("AI Builder mod initialized")
  storage.agent = nil
  storage.batches = {}
  storage.marks = {}
end)

script.on_configuration_changed(function(event)
  utils.info("AI Builder mod configuration changed")
  config.reload()
  -- Migrate storage if needed (handle mod updates)
  if not storage.batches then storage.batches = {} end
  if not storage.marks then storage.marks = {} end
end)

script.on_load(function()
  -- Factorio 2.0: storage persists, but entity references need to be re-resolved
  -- This is handled by agent.on_load()
  -- Minimal work in on_load per Factorio best practices
end)

-- ============================================================================
-- Tick Handler
-- ============================================================================

script.on_nth_tick(config.BATCH_TICK_INTERVAL, function(event)
  -- Batch builder state machine
  batch_builder.on_tick()
end)

-- Update map marker and visible rendering every 5 ticks (smooth movement)
script.on_nth_tick(5, function(event)
  agent_mod.update_chart_tag()
end)

-- ============================================================================
-- AI Command Completed (unit pathfinding)
-- ============================================================================

script.on_event(defines.events.on_ai_command_completed, function(event)
  movement.on_ai_command_completed(event)
end)

-- ============================================================================
-- Damage Event (Biter Immunity)
-- ============================================================================

script.on_event(defines.events.on_entity_damaged, function(event)
  biter_immunity.on_entity_damaged(event)
end)

-- ============================================================================
-- Chat Commands
-- ============================================================================

-- /ai-stop - Emergency stop
commands.add_command(config.EMERGENCY_STOP_CHAT_COMMAND,
  "AI Builder: Emergency stop - cancel all pending operations",
  function(cmd)
    local result = emergency_stop.trigger()
    if result then
      if cmd.player_index then
        game.players[cmd.player_index].print(
          "[AI Builder] Emergency stop triggered. Cancelled: " ..
          table.concat(result.cancelled_actions or {}, ", ")
        )
      end
    else
      if cmd.player_index then
        game.players[cmd.player_index].print("[AI Builder] No agent to stop.")
      end
    end
  end
)

-- /ai-reset - Reset emergency stop
commands.add_command(config.EMERGENCY_RESET_CHAT_COMMAND,
  "AI Builder: Reset emergency stop",
  function(cmd)
    local result = emergency_stop.reset()
    if result and result.reset then
      if cmd.player_index then
        game.players[cmd.player_index].print("[AI Builder] Emergency stop reset.")
      end
    else
      if cmd.player_index then
        game.players[cmd.player_index].print("[AI Builder] Not in emergency state.")
      end
    end
  end
)

-- /ai-mark [label] - Mark current area for AI
commands.add_command("ai-mark",
  "AI Builder: Mark area around current position or selected entity",
  function(cmd)
    if not cmd.player_index then return end
    local player = game.players[cmd.player_index]

    local label = cmd.parameter or "Player marked area"
    local pos = player.position

    -- Use selected entity if available
    local area
    if player.selected then
      local epos = player.selected.position
      area = {
        { epos.x - 8, epos.y - 8 },
        { epos.x + 8, epos.y + 8 },
      }
    else
      area = {
        { pos.x - 16, pos.y - 16 },
        { pos.x + 16, pos.y + 16 },
      }
    end

    local mark_id = "player_mark_" .. game.tick

    -- Register mark through area_query
    local result = area_query.create_mark(mark_id, area[1], area[2], label)

    if result and result.marked then
      player.print("[AI Builder] Area marked as '" .. mark_id .. "': " .. label)
    end
  end
)

-- /ai-status - Show agent status
commands.add_command("ai-status",
  "AI Builder: Show current agent status",
  function(cmd)
    if not cmd.player_index then return end
    local player = game.players[cmd.player_index]

    local state = agent_mod.get_state()
    if not state.exists then
      player.print("[AI Builder] No agent exists.")
      return
    end

    local lines = {
      "[AI Builder] Agent Status:",
      "  Position: " .. state.position.x .. ", " .. state.position.y,
      "  Health: " .. state.health .. "/" .. state.max_health,
      "  Moving: " .. tostring(state.is_moving),
      "  Emergency: " .. tostring(state.emergency_stopped),
      "  Current action: " .. (state.current_action and state.current_action.type or "none"),
      "  Pending actions: " .. state.pending_action_count,
      "  Inventory items: " .. state.inventory_total_items,
    }

    for _, line in ipairs(lines) do
      player.print(line)
    end
  end
)

-- /ai-templates - List available building templates
commands.add_command("ai-templates",
  "AI Builder: List available building templates",
  function(cmd)
    if not cmd.player_index then return end
    local player = game.players[cmd.player_index]
  local tlist = templates.list_with_descriptions()
    player.print("[AI Builder] Available building templates:")
    for _, t in ipairs(tlist) do
      player.print("  " .. t.name .. ": " .. t.description ..
        " (entities/unit: " .. t.entity_count_per_unit .. ")")
    end
  end
)

-- ============================================================================
-- Settings Changed (in-game mod settings panel)
-- ============================================================================

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting_type == "runtime-global" then
    local name = event.setting
    if name and name:find("^ai-builder-") then
      config.reload()
      utils.info("Mod setting changed: " .. name .. " → reloaded")
    end
  end
end)

-- ============================================================================
-- Note: Factorio 2.0 auto-persists the storage table.
-- No manual on_save hook needed.
-- If character references are lost on load, use unit_number to re-resolve.
-- ============================================================================

-- ============================================================================
-- Log startup
-- ============================================================================

utils.info("AI Builder mod loaded successfully")
utils.info("  Chat commands: /ai-stop, /ai-reset, /ai-mark, /ai-status, /ai-templates")
utils.info("  Remote interface: remote.call('ai_builder', ...) - " ..
  "see remote_interface.lua for full API")
