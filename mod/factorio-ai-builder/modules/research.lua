--[[
  Factorio AI Builder - Research Module
  Technology management.
--]]

local utils = require("__factorio-ai-builder__/modules/utils")
local agent = require("__factorio-ai-builder__/modules/agent")

local research = {}

function research.get_technologies(only_available)
  if not agent.exists() then
    return nil, "no_agent"
  end

  local entity = agent.get_entity()
  local force = entity.force

  local techs = {}
  for name, tech in pairs(prototypes.technology) do
    local force_tech = force.technologies[name]

    if not only_available or (force_tech and force_tech.enabled and not force_tech.researched) then
      -- Get science pack requirements
      local science_packs = {}
      if tech.research_unit_ingredients then
        for _, ing in ipairs(tech.research_unit_ingredients) do
          table.insert(science_packs, {
            name = ing.name,
            amount = ing.amount,
          })
        end
      end

      table.insert(techs, {
        name = name,
        researched = force_tech and force_tech.researched or false,
        enabled = force_tech and force_tech.enabled or false,
        level = force_tech and force_tech.level or 0,
        research_unit_count = tech.research_unit_count or 0,
        research_unit_energy = tech.research_unit_energy or 0,
        science_packs = science_packs,
        prerequisites = tech.prerequisites and tech._get_prerequisites_names() or {},
      })
    end
  end

  table.sort(techs, function(a, b) return a.name < b.name end)

  return { technologies = techs }
end

function research.enqueue_research(technology_name)
  if not agent.exists() then
    return nil, "no_agent"
  end

  local entity = agent.get_entity()
  local force = entity.force

  if not force.technologies[technology_name] then
    return nil, "unknown_technology", { technology_name = technology_name }
  end

  local tech = force.technologies[technology_name]
  if tech.researched then
    return nil, "already_researched"
  end

  if not tech.enabled then
    return nil, "technology_not_enabled"
  end

  -- Check if already being researched
  if force.current_research and force.current_research.name == technology_name then
    return { researching = true, technology = technology_name, progress = force.research_progress }
  end

  -- Set research
  force.current_research = technology_name

  return {
    researching = true,
    technology = technology_name,
    progress = force.research_progress,
  }
end

function research.cancel_current_research()
  if not agent.exists() then
    return nil, "no_agent"
  end

  local entity = agent.get_entity()
  local force = entity.force

  if not force.current_research then
    return nil, "no_active_research"
  end

  local name = force.current_research.name
  force.current_research = nil

  return { cancelled = true, technology = name }
end

function research.get_current_research()
  if not agent.exists() then
    return nil, "no_agent"
  end

  local force = agent.get_entity().force

  if not force.current_research then
    return { researching = false }
  end

  return {
    researching = true,
    technology = force.current_research.name,
    progress = force.research_progress,
  }
end

return research
