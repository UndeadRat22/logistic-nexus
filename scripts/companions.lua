-- Logistic Nexus
-- Companion entity management: requester, provider, inserters.

local C = require("scripts.constants")
local Util = require("scripts.util")
local Status = require("scripts.status")
local Network = require("scripts.network")

local M = {}

------------------------------------------------------------
-- COMPANION LAYOUT
------------------------------------------------------------

function M.companion_spec(workshop, name, dx, dy)
  return {
    name = name,
    position = {
      x = workshop.position.x + dx,
      y = workshop.position.y + dy
    }
  }
end

function M.companion_layout(workshop)
  return {
    requester = M.companion_spec(workshop, C.REQUESTER_NAME, 1.5, 0.5),
    provider = M.companion_spec(workshop, C.PROVIDER_NAME, 1.5, 1.5)
  }
end

local function find_expected_entity(surface, spec)
  local entity = surface.find_entity(spec.name, spec.position)
  if entity and entity.valid then
    return entity
  end

  return nil
end

local function can_create_companion(workshop, spec)
  if find_expected_entity(workshop.surface, spec) then
    return true
  end

  return workshop.surface.can_place_entity({
    name = spec.name,
    position = spec.position,
    direction = spec.direction,
    force = workshop.force
  })
end

local function create_or_get_companion(workshop, spec)
  local existing = find_expected_entity(workshop.surface, spec)
  if existing then
    return existing
  end

  return workshop.surface.create_entity({
    name = spec.name,
    position = spec.position,
    direction = spec.direction,
    force = workshop.force,
    create_build_effect_smoke = false,
    raise_built = false
  })
end

------------------------------------------------------------
-- REQUESTER CONFIGURATION
------------------------------------------------------------

function M.configure_requester(entity, trash_not_requested)
  if not (entity and entity.valid and entity.name == C.REQUESTER_NAME) then
    return
  end

  local logistic_point = entity.get_logistic_point
      and entity.get_logistic_point(defines.logistic_member_index.logistic_container)

  if not logistic_point then
    logistic_point = entity.get_logistic_point and entity.get_logistic_point()
  end

  if logistic_point and logistic_point.valid then
    logistic_point.trash_not_requested = trash_not_requested ~= false
  end
end

local function get_requester_section(requester, trash_not_requested)
  local point = Network.get_requester_point(requester)
  if not point then
    return nil
  end

  M.configure_requester(requester, trash_not_requested)

  if point.sections_count and point.sections_count > 0 then
    local ok, section = pcall(function()
      return point.get_section(1)
    end)

    if ok and section and section.valid then
      return section
    end
  end

  local ok, section = pcall(function()
    return point.add_section("Logistic Nexus")
  end)

  if ok and section and section.valid then
    return section
  end

  return nil
end

function M.clear_requester_requests(requester, trash_not_requested)
  local section = get_requester_section(requester, trash_not_requested)
  if not section then
    return
  end

  local clear_count = math.max(C.REQUEST_SLOT_CLEAR_COUNT, section.filters_count or 0)
  for slot = 1, clear_count do
    pcall(function()
      section.clear_slot(slot)
    end)
  end
end

function M.set_requester_requests(requester, ingredients)
  local section = get_requester_section(requester)
  if not section then
    return false
  end

  local clear_count = math.max(C.REQUEST_SLOT_CLEAR_COUNT, section.filters_count or 0, #ingredients)
  for slot = 1, clear_count do
    pcall(function()
      section.clear_slot(slot)
    end)
  end

  for index, ingredient in ipairs(ingredients) do
    local amount = Util.ingredient_count(ingredient)
    if not amount then
      return false
    end
    if amount > 0 then
      local quality = ingredient.quality or "normal"
      local ok = pcall(function()
        section.set_slot(index, {
          value = {
            type = "item",
            name = ingredient.name,
            quality = quality,
            comparator = "="
          },
          min = amount,
          max = amount
        })
      end)

      if not ok then
        return false
      end
    end
  end

  M.configure_requester(requester)
  return true
end

function M.freeze_requester_batch(requester)
  M.configure_requester(requester, false)
  M.clear_requester_requests(requester, false)
end

------------------------------------------------------------
-- COMPANION LIFECYCLE
------------------------------------------------------------

function M.destroy_entity(entity)
  if entity and entity.valid then
    entity.destroy()
  end
end

function M.destroy_companions(workshop_data)
  if not workshop_data then
    return
  end

  for _, companion in pairs(workshop_data.companions or {}) do
    if companion and companion.valid and companion.unit_number then
      storage.companion_owners[companion.unit_number] = nil
    end
    M.destroy_entity(companion)
  end

  workshop_data.companions = {}
end

function M.remove_unowned_companions()
  for _, surface in pairs(game.surfaces) do
    for name in pairs(C.COMPANION_NAMES) do
      for _, entity in pairs(surface.find_entities_filtered({name = name})) do
        if entity.unit_number and not storage.companion_owners[entity.unit_number] then
          M.destroy_entity(entity)
        end
      end
    end
  end
end

function M.ensure_companions(workshop)
  local layout = M.companion_layout(workshop)

  for _, spec in pairs(layout) do
    if not can_create_companion(workshop, spec) then
      Status.set_blocked_status(workshop)
      return nil
    end
  end

  local companions = {}
  local occupied_positions = {}

  for key, spec in pairs(layout) do
    local companion = create_or_get_companion(workshop, spec)
    if not (companion and companion.valid and companion.unit_number) then
      Status.set_blocked_status(workshop)
      return nil
    end

    local key_for_position = Util.position_key(spec.position)
    if occupied_positions[key_for_position] then
      Status.set_blocked_status(workshop)
      return nil
    end

    occupied_positions[key_for_position] = true
    companions[key] = companion
    if spec.direction then
      companion.direction = spec.direction
    end

    if companion.name == C.REQUESTER_NAME then
      M.configure_requester(companion)
    end

    storage.companion_owners[companion.unit_number] = workshop.unit_number
  end

  return companions
end

return M
