-- Logistic Nexus
-- Entity status display and goal sprite management.

local C = require("scripts.constants")

local M = {}

------------------------------------------------------------
-- STATUS
------------------------------------------------------------

function M.set_custom_status(entity, key, status)
  if entity and entity.valid then
    local unit_number = entity.unit_number
    if unit_number and storage.status_keys[unit_number] == key then
      return
    end

    if unit_number then
      storage.status_keys[unit_number] = key
    end
    entity.custom_status = status
  end
end

function M.set_idle_status(entity)
  M.set_custom_status(entity, "idle", {
    diode = defines.entity_status_diode.green,
    label = {"logistic-nexus.status-idle"}
  })
end

function M.set_blocked_status(entity)
  M.set_custom_status(entity, "blocked", {
    diode = defines.entity_status_diode.red,
    label = {"logistic-nexus.status-blocked"}
  })
end

function M.set_no_network_status(entity)
  M.set_custom_status(entity, "no-network", {
    diode = defines.entity_status_diode.red,
    label = {"logistic-nexus.status-no-network"}
  })
end

function M.set_no_shortage_status(entity, request_count, shortage_count)
  request_count = request_count or 0
  shortage_count = shortage_count or 0
  M.set_custom_status(entity, "no-shortage|" .. request_count .. "|" .. shortage_count, {
    diode = defines.entity_status_diode.yellow,
    label = {"logistic-nexus.status-no-shortage", request_count, shortage_count}
  })
end

function M.set_working_status(entity, item_name, shortage)
  M.set_custom_status(entity, "working|" .. (item_name or "") .. "|" .. (shortage or 0), {
    diode = defines.entity_status_diode.green,
    label = {"logistic-nexus.status-working", "[item=" .. item_name .. "]", shortage}
  })
end

function M.set_finishing_status(entity, item_name)
  M.set_custom_status(entity, "finishing|" .. (item_name or ""), {
    diode = defines.entity_status_diode.yellow,
    label = {"logistic-nexus.status-finishing", item_name and "[item=" .. item_name .. "]" or ""}
  })
end

------------------------------------------------------------
-- GOAL SPRITES
------------------------------------------------------------

function M.destroy_goal_sprite(workshop_data)
  local sprites = workshop_data and workshop_data.goal_sprites
  local old_sprite = workshop_data and workshop_data.goal_sprite
  local map_display = workshop_data and workshop_data.goal_map_display
  local world_display = workshop_data and workshop_data.goal_world_display

  if not sprites and old_sprite then
    sprites = {old_sprite}
  end

  if not sprites and not map_display and not world_display then
    return
  end

  for _, sprite in pairs(sprites or {}) do
    pcall(function()
      if type(sprite) == "number" then
        if rendering.is_valid(sprite) then
          rendering.destroy(sprite)
        end
      elseif sprite and sprite.valid then
        sprite.destroy()
      end
    end)
  end

  pcall(function()
    if map_display and map_display.valid then
      map_display.destroy()
    end
  end)

  pcall(function()
    if world_display and world_display.valid then
      world_display.destroy()
    end
  end)

  workshop_data.goal_sprites = nil
  workshop_data.goal_sprite = nil
  workshop_data.goal_sprite_item = nil
  workshop_data.goal_sprite_quality = nil
  workshop_data.goal_map_display = nil
  workshop_data.goal_map_recipe = nil
  workshop_data.goal_world_display = nil
  workshop_data.goal_world_recipe = nil
end

function M.destroy_all_goal_sprites()
  pcall(function()
    for _, object in pairs(rendering.get_all_objects("logistic-nexus")) do
      if object and object.valid then
        object.destroy()
      end
    end
  end)

  pcall(function()
    rendering.clear("logistic-nexus")
  end)

  for _, workshop_data in pairs(storage.workshops or {}) do
    M.destroy_goal_sprite(workshop_data)
  end

  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({name = C.MAP_DISPLAY_NAME})) do
      if entity.valid then
        entity.destroy()
      end
    end
    for _, entity in pairs(surface.find_entities_filtered({name = C.WORLD_DISPLAY_NAME})) do
      if entity.valid then
        entity.destroy()
      end
    end
  end
end

function M.set_goal_sprite(workshop_data, item_name, recipe_name, quality)
  local workshop = workshop_data and workshop_data.entity
  if not (workshop and workshop.valid) then
    return true
  end
  quality = quality or "normal"

  if workshop_data.goal_sprite_item == item_name
      and workshop_data.goal_sprite_quality == quality then
    local map_display_valid = workshop_data.goal_map_display
        and workshop_data.goal_map_display.valid
        and workshop_data.goal_map_recipe == recipe_name
    local world_display_valid = workshop_data.goal_world_display
        and workshop_data.goal_world_display.valid
        and workshop_data.goal_world_recipe == recipe_name
    if map_display_valid and world_display_valid then
      return
    end
  end

  M.destroy_goal_sprite(workshop_data)

  if not item_name then
    return
  end

  local map_display
  local world_display
  pcall(function()
    map_display = workshop.surface.create_entity({
      name = C.MAP_DISPLAY_NAME,
      position = workshop.position,
      force = workshop.force,
      create_build_effect_smoke = false
    })
    if map_display and map_display.valid then
      map_display.set_recipe(recipe_name, quality)
      map_display.active = false
    end
  end)

  pcall(function()
    world_display = workshop.surface.create_entity({
      name = C.WORLD_DISPLAY_NAME,
      position = workshop.position,
      force = workshop.force,
      create_build_effect_smoke = false
    })
    if world_display and world_display.valid then
      world_display.set_recipe(recipe_name, quality)
      world_display.active = false
    end
  end)

  if map_display or world_display then
    workshop_data.goal_sprites = nil
    workshop_data.goal_sprite_item = item_name
    workshop_data.goal_sprite_quality = quality
    workshop_data.goal_map_display = map_display
    workshop_data.goal_map_recipe = recipe_name
    workshop_data.goal_world_display = world_display
    workshop_data.goal_world_recipe = recipe_name
  end
end

return M
