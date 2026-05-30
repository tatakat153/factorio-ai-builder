--[[
  Factorio AI Builder - Data Stage
  Custom unit prototype: AI agent using native biter pathfinding.
  Looks like a character, moves like a unit (set_command with go_to_location).
--]]

local ai_builder_unit = {
  type = "unit",
  name = "ai-builder-agent",
  -- Localization
  localised_name = { "entity-name.ai-builder-agent" },
  -- Appearance: uses character sprites
  icon = "__base__/graphics/entity/character/level1_idle.png",
  icon_size = 64,
  flags = { "placeable-player", "placeable-enemy", "placeable-off-grid", "not-repairable", "breaths-air" },
  -- Small collision box like a character
  collision_box = { { -0.2, -0.2 }, { 0.2, 0.2 } },
  selection_box = { { -0.4, -0.4 }, { 0.4, 0.4 } },
  -- Movement
  has_belt_immunity = true,
  movement_speed = 0.15,  -- ~9 tiles/s, same as player character
  distance_per_frame = 0.15,
  -- No attack (required by prototype, but does nothing)
  attack_parameters = {
    type = "projectile",
    ammo_category = "bullet",
    range = 0,
    cooldown = 999999,
    ammo_type = {
      category = "bullet",
      target_type = "entity",
      action = {
        type = "direct",
        action_delivery = {
          type = "instant",
          target_effects = {
            { type = "damage", damage = { type = "physical", amount = 0 } }
          },
        },
      },
    },
    animation = {
      layers = {
        {
          filename = "__core__/graphics/empty.png",
          priority = "high",
          width = 1,
          height = 1,
          frame_count = 1,
          direction_count = 1,
        },
      },
    },
  },
  -- Vision (for radar-like reveal)
  vision_distance = 0,
  -- No pollution
  absorptions_to_join_attack = { pollution = 999999999 },
  -- Run animation (character sprites, no shadow for simplicity)
  run_animation = {
    layers = {
      {
        filename = "__base__/graphics/entity/character/level1_running.png",
        priority = "high",
        width = 88,
        height = 132,
        frame_count = 22,
        direction_count = 8,
        shift = { 0, -0.28125 },
        scale = 0.5,
      },
    },
  },
  -- Disable biter-specific behaviors
  allowed_to_cross_water = false,
  affected_by_tiles = true,
  distraction_cooldown = 0,
  min_pursue_time = 0,
  max_pursue_distance = 0,
  -- No death loot
  dying_explosion = nil,
  -- No sound
  dying_sound = nil,
  -- No corpse
  corpse = nil,
  -- Resistances
  resistances = {
    { type = "physical", decrease = 0, percent = 100 },  -- immune to physical
    { type = "acid", decrease = 0, percent = 100 },       -- immune to acid
    { type = "fire", decrease = 0, percent = 100 },       -- immune to fire
    { type = "explosion", decrease = 0, percent = 100 },  -- immune to explosion
  },
  -- No healing
  healing_per_tick = 0,
  -- Max health
  max_health = 1000,
}

data:extend({ ai_builder_unit })
