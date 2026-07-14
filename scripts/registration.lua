-- Logistic Nexus
-- Workshop registration, rebuild, and recipe sync.

local C = require("scripts.constants")
local Util = require("scripts.util")
local Storage = require("scripts.storage")
local Status = require("scripts.status")
local Network = require("scripts.network")
local Companions = require("scripts.companions")
local Construction = require("scripts.construction")
local Recipes = require("scripts.recipes")
local Brain = require("scripts.brain")
local Planner = require("scripts.planner")
local Workshop = require("scripts.workshop")

local M = {}

------------------------------------------------------------
-- WORKSHOP REGISTRATION
------------------------------------------------------------

function M.register_workshop(entity)
  Storage.init_storage()

  if not (entity and entity.valid and C.WORKSHOP_NAMES[entity.name] and entity.unit_number) then
    return
  end

  local x_fraction = entity.position.x - math.floor(entity.position.x)
  local y_fraction = entity.position.y - math.floor(entity.position.y)
  if math.abs(x_fraction - 0.5) < 0.01 and math.abs(y_fraction - 0.5) < 0.01 then
    entity.teleport({
      x = entity.position.x + 0.5,
      y = entity.position.y - 0.5
    })
  end

  local existing = storage.workshops[entity.unit_number]
  if existing then
    Companions.destroy_companions(existing)
  end

  local companions = Companions.ensure_companions(entity)
  local active_recipe, active_quality = entity.get_recipe()
  local active_item = nil

  if active_recipe and (
      (entity.crafting_progress and entity.crafting_progress > 0)
      or Workshop.output_inventory_has_items(entity)) then
    for _, product in pairs(active_recipe.products or {}) do
      if product.type == "item" then
        active_item = product.name
        break
      end
    end
  else
    active_recipe = nil
  end

  storage.workshops[entity.unit_number] = {
    entity = entity,
    companions = companions or {},
    assignment = nil,
    current_item = active_item,
    current_quality = Util.quality_name(active_quality),
    current_shortage = 0,
    current_recipe = active_recipe and active_recipe.name or nil,
    last_products_finished = entity.products_finished or 0,
    recorded_products_finished = entity.products_finished or 0,
    current_product_amount = 1,
    current_is_construction = false,
    current_construction_target = 0,
    current_construction_reserved = 0,
    waiting_for_clear = nil
  }

  if companions then
    Status.set_idle_status(entity)
  end
end

function M.unregister_workshop(entity, destroy_workshop)
  if not (entity and entity.unit_number) then
    return
  end

  local workshop_data = storage.workshops[entity.unit_number]
  Status.destroy_goal_sprite(workshop_data)
  Companions.destroy_companions(workshop_data)
  storage.workshops[entity.unit_number] = nil
  storage.status_keys[entity.unit_number] = nil

  if destroy_workshop then
    Companions.destroy_entity(entity)
  end
end

function M.unregister_companion(entity)
  if not (entity and entity.unit_number) then
    return
  end

  local workshop_unit_number = storage.companion_owners[entity.unit_number]
  if not workshop_unit_number then
    return
  end

  local workshop_data = storage.workshops[workshop_unit_number]
  if not workshop_data then
    storage.companion_owners[entity.unit_number] = nil
    return
  end

  M.unregister_workshop(workshop_data.entity, true)
end

------------------------------------------------------------
-- REBUILD
------------------------------------------------------------

local function return_inventory_to_provider(workshop_data, inventory, allow_spill)
  if not (inventory and inventory.valid) then
    return true
  end

  local fully_drained = true

  for _, item in pairs(inventory.get_contents() or {}) do
    local count = item.count or 0

    if item.name and count > 0 then
      local stack = Util.stack_definition(item.name, count, item.quality)
      local removed = inventory.remove(stack)

      if removed > 0 then
        local returned = {
          name = item.name,
          count = removed,
          quality = item.quality
        }

        if allow_spill == false then
          local remaining = Workshop.insert_into_output_containers(workshop_data, returned)
          if remaining then
            inventory.insert(remaining)
            fully_drained = false
          end
        elseif not Workshop.insert_or_spill_item(workshop_data, returned, true) then
          fully_drained = false
        end
      end
    end
  end

  return fully_drained
end

function M.release_workshop_for_rebuild(workshop_data)
  local workshop = workshop_data and workshop_data.entity
  if not (workshop and workshop.valid) then
    return
  end

  local fully_drained = true
  if workshop_data.assignment then
    local internal = workshop_data.assignment.internal_inventory or {}
    for key, count in pairs(internal) do
      if count > 0 then
        local name, quality = Util.split_item_key(key)
        local remaining = Workshop.insert_into_output_containers(workshop_data, {
          name = name,
          quality = quality,
          count = count
        })

        if remaining then
          internal[key] = remaining.count
          fully_drained = false
        else
          internal[key] = nil
        end
      end
    end
  end

  Workshop.set_workshop_recipe(workshop_data, nil)

  local ok, input_inventory = pcall(function()
    return workshop.get_inventory(defines.inventory.crafter_input)
  end)
  if ok then
    fully_drained = return_inventory_to_provider(
      workshop_data,
      input_inventory,
      false
    ) and fully_drained
  end

  fully_drained = return_inventory_to_provider(
    workshop_data,
    workshop.get_output_inventory(),
    false
  ) and fully_drained

  local requester = workshop_data.companions and workshop_data.companions.requester
  if requester and requester.valid then
    fully_drained = return_inventory_to_provider(
      workshop_data,
      requester.get_inventory(defines.inventory.chest),
      false
    ) and fully_drained
    if fully_drained then
      Companions.clear_requester_requests(requester)
    end
  end

  return fully_drained
end

function M.rebuild_workshops()
  local fully_drained = true
  for _, workshop_data in pairs(storage.workshops or {}) do
    fully_drained = M.release_workshop_for_rebuild(workshop_data) and fully_drained
  end

  if not fully_drained then
    return
  end

  Status.destroy_all_goal_sprites()
  storage.workshops = {}
  storage.companion_owners = {}

  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({name = {C.WORKSHOP_NAME, C.WORKSHOP_MK2_NAME}})) do
      M.register_workshop(entity)
    end
  end

  Companions.remove_unowned_companions()
end

------------------------------------------------------------
-- RECIPE SYNC
------------------------------------------------------------

local function reset_force_recipe_effects(force)
  if not force then
    return
  end

  pcall(function()
    force.reset_recipes()
  end)
  pcall(function()
    force.reset_technology_effects()
  end)
end

local function invalidate_force_recipe_caches(force)
  Recipes.invalidate_recipe_index(force)

  for _, brain in pairs(storage.brains or {}) do
    if not force or brain.force_name == force.name then
      brain.recipe_choices = {}
      brain.raw_supply_counts = {}
      brain.schedule_dirty = true
      brain.next_schedule_tick = 0
    end
  end
end

local function sync_force_barrelled_recipes(force)
  if not force then
    return
  end

  for recipe_name, recipe in pairs(force.recipes) do
    if type(recipe_name) == "string"
        and string.sub(recipe_name, 1, #C.BARRELLED_RECIPE_PREFIX) == C.BARRELLED_RECIPE_PREFIX then
      local source_name = string.sub(recipe_name, #C.BARRELLED_RECIPE_PREFIX + 1)
      local source_recipe = force.recipes[source_name]

      if source_recipe then
        recipe.enabled = source_recipe.enabled
      else
        recipe.enabled = false
      end
    end
  end
end

function M.sync_barrelled_recipes(force, options)
  options = options or {}
  storage.last_barrelled_recipe_sync = game.tick
  storage.barrelled_recipe_effects_reset = nil

  if force then
    if options.reset_force_effects then
      reset_force_recipe_effects(force)
    end
    sync_force_barrelled_recipes(force)
    invalidate_force_recipe_caches(force)
    return
  end

  for _, current_force in pairs(game.forces) do
    if options.reset_force_effects then
      reset_force_recipe_effects(current_force)
    end
    sync_force_barrelled_recipes(current_force)
  end

  invalidate_force_recipe_caches()
end

return M

