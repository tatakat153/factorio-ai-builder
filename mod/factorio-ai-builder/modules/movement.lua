--[[
  Factorio AI Builder - Movement Module (Unit-based)
  Uses native Factorio unit pathfinding via commandable.set_command(go_to_location).
  
  Key behaviors:
  - If goal is unreachable (inside obstacle), unit completes near the obstacle.
    We detect this as "stuck" and report the obstacle at the goal position.
  - approach_to(target, distance): walk to within distance of target,
    avoiding the "goal inside obstacle" problem for mining/placing.
--]]

local defines = defines
local config = require("__factorio-ai-builder__/config")
local utils = require("__factorio-ai-builder__/modules/utils")
local agent_mod = require("__factorio-ai-builder__/modules/agent")

local movement = {}

-- ============================================================================
-- Walk State Structure (in storage.agent.walk_state)
-- ============================================================================
-- {
--   goal: {x, y},
--   state: "walking" | "arrived" | "stuck",
--   stuck_position: {x, y} | nil,
--   stuck_obstacle: {name, position} | nil,
--   command_id: number,
-- }

-- ============================================================================
-- Public API
-- ============================================================================

function movement.walk_to(goal, strict_goal)
  if not agent_mod.exists() then return nil, "no_agent" end
  if storage.agent.emergency_stopped then return nil, "emergency_stopped" end

  local entity = agent_mod.get_entity()
  local goal_pos = utils.table_to_position(goal)
  if not goal_pos then return nil, "invalid_goal" end

  entity.commandable.set_command({
    type = defines.command.go_to_location,
    destination = goal_pos,
    distraction = defines.distraction.none,
    pathfind_flags = { allow_paths_through_own_entities = true },
  })

  storage.agent.walk_state = {
    goal = goal_pos,
    state = "walking",
    command_id = game.tick,
  }

  agent_mod.set_current_action("walking", { goal = goal_pos })
  return true
end

-- Walk to a point near the target, at approximately `distance` tiles away.
-- Useful for mining/placing: don't walk INTO the target, walk just outside reach.
function movement.approach_to(target, distance)
  if not agent_mod.exists() then return nil, "no_agent" end
  if storage.agent.emergency_stopped then return nil, "emergency_stopped" end

  local entity = agent_mod.get_entity()
  local target_pos = utils.table_to_position(target)
  if not target_pos then return nil, "invalid_target" end

  local dist = distance or agent_mod.get_build_distance() - 1

  -- Compute approach point: from target toward agent, at the edge of reach
  local dx = entity.position.x - target_pos.x
  local dy = entity.position.y - target_pos.y
  local current_dist = math.sqrt(dx * dx + dy * dy)

  local goal_pos
  if current_dist < 0.1 then
    -- Agent is right on the target, move a bit away first
    goal_pos = { x = target_pos.x, y = target_pos.y - dist }
  elseif current_dist <= dist then
    -- Already close enough
    storage.agent.walk_state = {
      goal = target_pos,
      state = "arrived",
      command_id = game.tick,
    }
    agent_mod.clear_current_action()
    return true
  else
    -- Compute point along the line from target to agent, at distance `dist`
    local ratio = dist / current_dist
    goal_pos = {
      x = target_pos.x + dx * ratio,
      y = target_pos.y + dy * ratio,
    }
  end

  return movement.walk_to(goal_pos)
end

function movement.stop()
  if not agent_mod.exists() then return false end
  local entity = agent_mod.get_entity()
  entity.commandable.set_command({ type = defines.command.stop })
  storage.agent.walk_state = nil
  agent_mod.clear_current_action()
  return true
end

function movement.get_status()
  if not storage.agent.walk_state then
    return { state = "idle" }
  end

  local ws = storage.agent.walk_state
  local entity = agent_mod.get_entity()

  return {
    state = ws.state,
    goal = ws.goal,
    position = utils.position_to_table(entity.position),
    stuck_position = ws.stuck_position,
    stuck_obstacle = ws.stuck_obstacle,
  }
end

-- ============================================================================
-- AI Command Completed Event
-- ============================================================================

function movement.on_ai_command_completed(event)
  if not storage.agent or not storage.agent.walk_state then return end
  if not agent_mod.exists() then return end

  local entity = agent_mod.get_entity()
  if event.unit_number ~= entity.unit_number then return end

  local ws = storage.agent.walk_state
  local dist = utils.distance(entity.position, ws.goal)

  if dist < 2 then
    -- Close enough
    ws.state = "arrived"
    agent_mod.clear_current_action()
    return
  end

  -- Command completed but not near goal.
  -- Unit pathfinding couldn't reach the exact point (likely inside an obstacle).
  -- Check what's at the goal position.
  local surface = entity.surface
  local entities_at_goal = surface.find_entities_filtered {
    area = {
      { ws.goal.x - 0.5, ws.goal.y - 0.5 },
      { ws.goal.x + 0.5, ws.goal.y + 0.5 },
    },
  }

  local obstacle = nil
  if entities_at_goal and #entities_at_goal > 0 then
    local e = entities_at_goal[1]
    obstacle = {
      name = e.name,
      type = e.type,
      position = utils.position_to_table(e.position),
      unit_number = e.unit_number,
    }
  end

  ws.state = "stuck"
  ws.stuck_position = utils.position_to_table(entity.position)
  ws.stuck_obstacle = obstacle

  utils.info(string.format("walk: goal unreachable (dist=%.1f), obstacle at goal: %s",
    dist, obstacle and obstacle.name or "unknown"))

  agent_mod.clear_current_action()
end

return movement
