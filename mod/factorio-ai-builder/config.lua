--[[
  Factorio AI Builder - Configuration
  Static constants + runtime settings from mod settings panel.
  
  Usage:
    local config = require("__factorio-ai-builder__/config")
    
    -- Static values are direct:
    local name = config.AGENT_FORCE_NAME
    
    -- Runtime settings are accessed via getters:
    local n = config.get("BATCH_PLACEMENTS_PER_TICK")
    
    -- Or call reload() after settings change:
    config.reload()
--]]

local config = {}

-- ============================================================================
-- Static Constants (never change at runtime)
-- ============================================================================

config.AGENT_FORCE_NAME = "player"
config.AGENT_ENTITY_NAME = "ai-builder-agent"
config.EMERGENCY_STOP_CHAT_COMMAND = "ai-stop"
config.EMERGENCY_RESET_CHAT_COMMAND = "ai-reset"
config.DEBUG_LOG_PREFIX = "[AI-Builder]"

-- ============================================================================
-- Runtime Settings (read from mod settings, with defaults)
-- ============================================================================

-- Internal storage with defaults
local _defaults = {
  DEBUG_MODE = false,
  BITER_IMMUNITY = true,
  MOVEMENT_STUCK_THRESHOLD_TICKS = 120,
  MOVEMENT_WAYPOINT_REACHED_DISTANCE = 1.5,
  MOVEMENT_REPATH_MAX_RETRIES = 3,
  BATCH_PLACEMENTS_PER_TICK = 3,
  BATCH_TICK_INTERVAL = 1,
  OVERVIEW_CHUNK_SIZE = 32,
  MARK_DETAIL_COMPRESSION_ENABLED = true,
  INVENTORY_MAX_SUMMARY_ITEMS = 20,
}

-- Current values (initialize with defaults)
for k, v in pairs(_defaults) do
  config[k] = v
end

-- ============================================================================
-- Settings Mapping (config key → mod setting name)
-- ============================================================================

local _setting_map = {
  DEBUG_MODE = "ai-builder-debug-mode",
  BITER_IMMUNITY = "ai-builder-biter-immunity",
  MOVEMENT_STUCK_THRESHOLD_TICKS = "ai-builder-movement-stuck-threshold",
  BATCH_PLACEMENTS_PER_TICK = "ai-builder-batch-placements-per-tick",
  OVERVIEW_CHUNK_SIZE = "ai-builder-overview-chunk-size",
}

-- ============================================================================
-- Reload from mod settings
-- ============================================================================

function config.reload()
  for config_key, setting_name in pairs(_setting_map) do
    local value = settings.global[setting_name]
    if value ~= nil then
      config[config_key] = value.value or _defaults[config_key]
    else
      config[config_key] = _defaults[config_key]
    end
  end

  -- Keep non-mapped values at defaults
  for k, v in pairs(_defaults) do
    if not _setting_map[k] and config[k] == nil then
      config[k] = v
    end
  end

  if config.DEBUG_MODE then
    log(config.DEBUG_LOG_PREFIX .. " Config reloaded from mod settings")
  end
end

-- ============================================================================
-- Getter (for explicit reads)
-- ============================================================================

function config.get(key)
  return config[key] or _defaults[key]
end

-- ============================================================================
-- Initialize with defaults on first load
-- ============================================================================

config.reload()

return config
