--[[
  Factorio AI Builder - Utilities
  Serialization, math helpers, validation.
--]]

local config = require("__factorio-ai-builder__/config")

local utils = {}

-- ============================================================================
-- Position & Math
-- ============================================================================

function utils.distance(a, b)
  return ((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) ^ 0.5
end

function utils.manhattan_distance(a, b)
  return math.abs(a.x - b.x) + math.abs(a.y - b.y)
end

function utils.direction_toward(from, to)
  local dx = to.x - from.x
  local dy = to.y - from.y

  -- Factorio defines direction 0 = north, increments clockwise
  -- north=0, northeast=1, east=2, southeast=3, south=4, southwest=5, west=6, northwest=7
  if math.abs(dx) < 0.1 and math.abs(dy) < 0.1 then
    return nil -- same position
  end

  local angle = math.atan2(dx, -dy) -- Factorio: negative y is north
  -- Normalize to [0, 2π)
  if angle < 0 then angle = angle + 2 * math.pi end

  -- Convert to 8-direction
  local eighth = math.floor((angle + math.pi / 8) / (math.pi / 4)) % 8
  return eighth
end

function utils.position_to_table(pos)
  if not pos then return nil end
  return { x = pos.x, y = pos.y }
end

function utils.table_to_position(t)
  if not t then return nil end
  return { x = t.x or t[1], y = t.y or t[2] }
end

-- ============================================================================
-- Serialization (Lua table → JSON string for RCON transport)
-- ============================================================================

-- Simple JSON encoder (no dependencies, handles Factorio's Lua tables)
local function json_encode_value(v, indent_level, visited)
  local t = type(v)

  if t == "nil" then
    return "null"
  elseif t == "boolean" then
    return v and "true" or "false"
  elseif t == "number" then
    if v ~= v then return "null" end -- NaN
    if v == math.huge then return "1e999" end
    if v == -math.huge then return "-1e999" end
    return string.format("%.17g", v)
  elseif t == "string" then
    -- Escape string for JSON
    local escaped = v
      :gsub("\\", "\\\\")
      :gsub('"', '\\"')
      :gsub("\n", "\\n")
      :gsub("\r", "\\r")
      :gsub("\t", "\\t")
    return '"' .. escaped .. '"'
  elseif t == "table" then
    if visited[v] then
      return '"<circular>"'
    end
    visited[v] = true

    -- Check if array-like (all keys are sequential integers starting at 1)
    local is_array = true
    local max_idx = 0
    local count = 0
    for k, _ in pairs(v) do
      if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
        is_array = false
        break
      end
      if k > max_idx then max_idx = k end
      count = count + 1
    end
    if is_array and max_idx ~= count then
      is_array = false -- sparse array → object
    end

    if is_array then
      local parts = {}
      for i = 1, max_idx do
        parts[i] = json_encode_value(v[i], indent_level, visited)
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local parts = {}
      local sorted_keys = {}
      for k, _ in pairs(v) do
        table.insert(sorted_keys, tostring(k))
      end
      table.sort(sorted_keys)

      for _, sk in ipairs(sorted_keys) do
        local key = sk
        -- Try numeric key
        local nk = tonumber(sk)
        if nk then key = nk end

        local encoded_key
        if type(key) == "number" then
          encoded_key = '"' .. tostring(key) .. '"'
        else
          encoded_key = json_encode_value(key, indent_level, visited)
        end
        local encoded_val = json_encode_value(v[key], indent_level, visited)
        table.insert(parts, encoded_key .. ":" .. encoded_val)
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  else
    return '"<' .. t .. '>"'
  end
end

function utils.to_json(tbl)
  return json_encode_value(tbl, 0, {})
end

-- Fast path: encode a simple object to JSON
function utils.to_json_compact(tbl)
  return json_encode_value(tbl, 0, {})
end

-- ============================================================================
-- Entity helpers
-- ============================================================================

function utils.get_entity_at(surface, position, name_filter)
  local entities
  if name_filter then
    entities = surface.find_entities_filtered {
      position = position,
      name = name_filter,
      limit = 1,
    }
  else
    entities = surface.find_entities_filtered {
      position = position,
      limit = 1,
    }
  end
  if entities and #entities > 0 then
    return entities[1]
  end
  return nil
end

function utils.can_place_entity(surface, position, entity_name, force)
  -- Check if the entity can be placed (no collision, within build range, etc.)
  -- This is a simplified check; Factorio's actual placement rules are complex
  local existing = surface.find_entities_filtered {
    area = {
      { position.x - 0.5, position.y - 0.5 },
      { position.x + 0.5, position.y + 0.5 },
    },
    limit = 1,
  }
  if existing and #existing > 0 then
    return false, "occupied_by", existing[1]
  end

  return true
end

-- ============================================================================
-- Logging
-- ============================================================================

function utils.debug(msg)
  if config.DEBUG_MODE then
    log(config.DEBUG_LOG_PREFIX .. " " .. msg)
  end
end

function utils.info(msg)
  log(config.DEBUG_LOG_PREFIX .. " " .. msg)
end

-- ============================================================================
-- Direction helpers
-- ============================================================================

-- Factorio direction constants
utils.DIRECTIONS = {
  NORTH = 0,
  NORTHEAST = 1,
  EAST = 2,
  SOUTHEAST = 3,
  SOUTH = 4,
  SOUTHWEST = 5,
  WEST = 6,
  NORTHWEST = 7,
}

utils.DIRECTION_VECTORS = {
  [0] = { x = 0, y = -1 },   -- north
  [1] = { x = 1, y = -1 },   -- northeast
  [2] = { x = 1, y = 0 },    -- east
  [3] = { x = 1, y = 1 },    -- southeast
  [4] = { x = 0, y = 1 },    -- south
  [5] = { x = -1, y = 1 },   -- southwest
  [6] = { x = -1, y = 0 },   -- west
  [7] = { x = -1, y = -1 },  -- northwest
}

return utils
