--[[
  Factorio AI Builder - Mod Settings
  Appears in Settings → Mod Settings → Map tab in-game.
  Descriptions are in locale/en/locale.cfg
--]]

data:extend({
  -- ========================================
  -- Connection Info (read-only, single-value)
  -- ========================================
  {
    type = "string-setting",
    name = "ai-builder-bridge-info",
    setting_type = "runtime-global",
    default_value = "Bridge: localhost:9380 | RCON: 127.0.0.1:34198",
    allowed_values = { "Bridge: localhost:9380 | RCON: 127.0.0.1:34198" },
    order = "a-a",
  },
  {
    type = "string-setting",
    name = "ai-builder-model-hint",
    setting_type = "runtime-global",
    default_value = "Planner (strong model) + Executor (cheap model)",
    allowed_values = { "Planner (strong model) + Executor (cheap model)" },
    order = "a-b",
  },

  -- ========================================
  -- Agent
  -- ========================================
  {
    type = "bool-setting",
    name = "ai-builder-biter-immunity",
    setting_type = "runtime-global",
    default_value = true,
    order = "b",
  },

  -- ========================================
  -- Movement
  -- ========================================
  {
    type = "int-setting",
    name = "ai-builder-movement-stuck-threshold",
    setting_type = "runtime-global",
    default_value = 120,
    minimum_value = 30,
    maximum_value = 600,
    order = "c",
  },

  -- ========================================
  -- Batch Building
  -- ========================================
  {
    type = "int-setting",
    name = "ai-builder-batch-placements-per-tick",
    setting_type = "runtime-global",
    default_value = 3,
    minimum_value = 1,
    maximum_value = 20,
    order = "d",
  },

  -- ========================================
  -- Area Query
  -- ========================================
  {
    type = "int-setting",
    name = "ai-builder-overview-chunk-size",
    setting_type = "runtime-global",
    default_value = 32,
    minimum_value = 8,
    maximum_value = 128,
    order = "e",
  },

  -- ========================================
  -- Debug
  -- ========================================
  {
    type = "bool-setting",
    name = "ai-builder-debug-mode",
    setting_type = "runtime-global",
    default_value = false,
    order = "z",
  },
})
