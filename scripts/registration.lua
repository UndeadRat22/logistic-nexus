-- AG Mall
-- Workshop registration, debug commands, rebuild, and recipe sync.

local C = require("scripts.constants")
local Util = require("scripts.util")
local Storage = require("scripts.storage")
local Status = require("scripts.status")
local Network = require("scripts.network")
local Companions = require("scripts.companions")
local Construction = require("scripts.construction")
local Recipes = require("scripts.recipes")
local Brain = require("scripts.brain")
local Workshop = require("scripts.workshop")

local M = {}

-- Forward declaration for circular dependency (sync_barrelled_recipes is defined below)
local sync_barrelled_recipes

------------------------------------------------------------
-- WORKSHOP REGISTRATION
------------------------------------------------------------

function M.register_workshop(entity)
  Storage.init_storage()

  if not (entity and entity.valid and entity.name == C.WORKSHOP_NAME and entity.unit_number) then
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
    for _, entity in pairs(surface.find_entities_filtered({name = C.WORKSHOP_NAME})) do
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

------------------------------------------------------------
-- DEBUG COMMANDS
------------------------------------------------------------

local function find_debug_workshop(player)
  local selected = player and player.selected
  if selected and selected.valid and selected.name == C.WORKSHOP_NAME and selected.unit_number then
    return storage.workshops[selected.unit_number]
  end

  for _, workshop_data in pairs(storage.workshops or {}) do
    local workshop = workshop_data and workshop_data.entity
    if workshop and workshop.valid and workshop.force == player.force then
      return workshop_data
    end
  end

  return nil
end

function M.debug_mall_item(player, item_name)
  Storage.init_storage()
  if M.sync_barrelled_recipes then
    M.sync_barrelled_recipes()
  end

  local workshop_data = find_debug_workshop(player)
  if not workshop_data then
    player.print("AG Mall debug: no AG Mall workshop found for this force.")
    return
  end

  local network = Network.get_network_for_workshop(workshop_data)
  if not network then
    player.print("AG Mall debug: selected AG Mall is outside a logistic network.")
    return
  end

  local recipe, product_amount = Recipes.find_recipe_for_item(workshop_data.entity, network.force, item_name)
  if not recipe then
    local source_recipe = network.force.recipes[item_name]
    local barrelled_recipe = network.force.recipes[C.BARRELLED_RECIPE_PREFIX .. item_name]

    player.print("AG Mall debug: no enabled AG Mall-compatible recipe for " .. item_name .. ".")
    if source_recipe then
      player.print(
        "AG Mall debug: source recipe "
            .. source_recipe.name
            .. " enabled="
            .. tostring(source_recipe.enabled)
            .. ", hidden="
            .. tostring(source_recipe.hidden)
            .. "."
      )
      -- Diagnostic: why does recipe_can_make_item reject this recipe?
      local workshop = workshop_data.entity
      if workshop and workshop.valid then
        local cats = workshop.prototype and workshop.prototype.crafting_categories
        local cat_str = ""
        if cats then
          for k, v in pairs(cats) do
            local c = type(k) == "string" and k or v
            cat_str = cat_str .. tostring(c) .. " "
          end
        end
        player.print("AG Mall debug: workshop crafting_categories: [" .. cat_str .. "]")
        if source_recipe.valid then
          local src_cat = source_recipe.category
          local src_cat_str = src_cat and tostring(src_cat) or ""
          player.print("AG Mall debug: recipe category: [" .. src_cat_str .. "]")
          local has_cat = false
          if cats then
            for k, v in pairs(cats) do
              local c = type(k) == "string" and k or v
              if type(c) == "string" and source_recipe.has_category(c) then
                has_cat = true
                break
              end
            end
          end
          player.print("AG Mall debug: recipe_has_supported_category=" .. tostring(has_cat))
          local pa = Recipes.recipe_product_amount(source_recipe, item_name)
          player.print("AG Mall debug: recipe_product_amount=" .. tostring(pa))
          local ings = Recipes.recipe_item_ingredients(source_recipe)
          player.print("AG Mall debug: recipe_item_ingredients=" .. tostring(ings and #ings or "nil"))
          player.print("AG Mall debug: recipe.products count=" .. tostring(#(source_recipe.products or {})))
          for _, p in pairs(source_recipe.products or {}) do
            player.print("AG Mall debug:   product: type=" .. tostring(p.type) .. " name=" .. tostring(p.name) .. " amount=" .. tostring(p.amount) .. " amount_min=" .. tostring(p.amount_min) .. " amount_max=" .. tostring(p.amount_max) .. " probability=" .. tostring(p.probability))
          end
        end
      end
    end
    if barrelled_recipe then
      player.print(
        "AG Mall debug: barrelled recipe "
            .. barrelled_recipe.name
            .. " enabled="
            .. tostring(barrelled_recipe.enabled)
            .. ", hidden="
            .. tostring(barrelled_recipe.hidden)
            .. "."
      )
    end
    return
  end

  local ingredients = Recipes.recipe_item_ingredients(recipe) or {}
  player.print(
    "AG Mall debug: "
        .. item_name
        .. " uses "
        .. recipe.name
        .. " and produces "
        .. (product_amount or 0)
        .. "."
  )

  for _, ingredient in pairs(ingredients) do
    local available = Network.get_available_count(network, ingredient.name, "normal")
    player.print(
      "AG Mall debug: ingredient "
          .. ingredient.name
          .. " need "
          .. (Util.ingredient_count(ingredient) or 0)
          .. ", available "
          .. available
          .. "."
    )
  end
end

function M.debug_construction_item(player, item_name)
  Storage.init_storage()

  if not (player and item_name and item_name ~= "") then
    return
  end

  local network
  local selected = player.selected
  if selected and selected.valid and selected.name == C.WORKSHOP_NAME then
    local workshop_data = selected.unit_number and storage.workshops[selected.unit_number]
    network = workshop_data and Network.get_network_for_workshop(workshop_data)
  end

  if not (network and network.valid) then
    network = player.surface.find_logistic_network_by_position(player.position, player.force)
  end

  if not (network and network.valid) then
    player.print("AG Mall construction debug: no logistic network at player or selected AG Mall.")
    return
  end

  local surface, blocks = Construction.construction_scan_blocks(network)
  if not (surface and blocks and #blocks > 0) then
    player.print("AG Mall construction debug: selected network has no construction scan area.")
    return
  end

  local seen = {}
  local scanned = 0
  local matching = 0
  local registered = 0
  local in_network = 0
  local counted = 0
  local counted_items = 0
  local samples = {}

  local function add_sample(reason, entity)
    if #samples >= 5 then
      return
    end

    local position = entity and entity.position or {x = 0, y = 0}
    table.insert(samples, string.format(
      "%s at %.1f, %.1f",
      reason,
      position.x or 0,
      position.y or 0
    ))
  end

  local function inspect_construction_entity(construction_entity, entity_key, registration_kind)
    if not (construction_entity and construction_entity.valid) then
      return
    end

    if seen[entity_key] then
      return
    end

    seen[entity_key] = true
    scanned = scanned + 1

    local match_count = 0
    for _, item in pairs(Construction.construction_entity_items(construction_entity)) do
      if item.name == item_name then
        match_count = match_count + (item.count or 1)
      end
    end

    if match_count <= 0 then
      return
    end

    matching = matching + 1

    local is_registered = true
    if registration_kind == "construction" then
      local ok, value = pcall(function()
        return construction_entity.is_registered_for_construction()
      end)
      is_registered = ok and value
    elseif registration_kind == "upgrade" then
      local ok, value = pcall(function()
        return construction_entity.is_registered_for_upgrade()
      end)
      is_registered = ok and value
    end

    if is_registered then
      registered = registered + 1
    else
      add_sample("not registered", construction_entity)
    end

    local belongs_to_network = false
    for _, candidate_network in pairs(
      surface.find_logistic_networks_by_construction_area(
        construction_entity.position,
        network.force
      )
    ) do
      if candidate_network
          and candidate_network.valid
          and candidate_network.network_id == network.network_id then
        belongs_to_network = true
        break
      end
    end

    if belongs_to_network then
      in_network = in_network + 1
      counted = counted + 1
      counted_items = counted_items + match_count
    else
      add_sample("outside selected network", construction_entity)
    end
  end

  for _, area in pairs(blocks) do
    for _, construction_entity in pairs(surface.find_entities_filtered({
      area = area,
      force = network.force,
      type = C.CONSTRUCTION_REQUEST_TYPES
    })) do
      inspect_construction_entity(
        construction_entity,
        "construction:" .. Construction.ghost_key(construction_entity),
        "construction"
      )
    end

    for _, upgrade_entity in pairs(surface.find_entities_filtered({
      area = area,
      force = network.force
    })) do
      if Construction.entity_upgrade_target(upgrade_entity) then
        inspect_construction_entity(
          upgrade_entity,
          "upgrade:" .. Construction.ghost_key(upgrade_entity),
          "upgrade"
        )
      end
    end
  end

  local reserved = Construction.get_construction_reservation(network, item_name, "normal", counted_items)
  player.print(string.format(
    "AG Mall construction debug: %s scanned=%d matching=%d registered=%d in-network=%d counted-ghosts=%d counted-items=%d reserved=%d net=%s.",
    item_name,
    scanned,
    matching,
    registered,
    in_network,
    counted,
    counted_items,
    reserved,
    tostring(network.network_id)
  ))

  for _, sample in ipairs(samples) do
    player.print("AG Mall construction debug: " .. sample)
  end
end

function M.debug_status(command)
  local player = command.player_index and game.get_player(command.player_index)
  local emit = player
      and function(message) player.print(message) end
      or function(message) log(message) end
  local target_limit = math.max(
    1,
    math.min(100, tonumber(command.parameter) or 25)
  )

  local network
  local selected = player and player.selected
  if selected and selected.valid and selected.name == C.WORKSHOP_NAME then
    local workshop_data = selected.unit_number and storage.workshops[selected.unit_number]
    network = workshop_data and Network.get_network_for_workshop(workshop_data)
  end

  if player and not (network and network.valid) then
    network = player.surface.find_logistic_network_by_position(player.position, player.force)
  end

  if not player and storage.brains then
    local largest = 0
    for _, candidate in pairs(storage.brains) do
      local count = #(candidate.workshops or {})
      if candidate.network and candidate.network.valid and count > largest then
        network = candidate.network
        largest = count
      end
    end
  end

  if not (network and network.valid) then
    emit("AG Mall: no logistic network at the player or selected mall.")
    return
  end

  local brain = storage.brains and storage.brains[Util.brain_key(network)]
  local analysis = brain and brain.last_analysis
  if not analysis then
    emit("AG Mall: this network has not completed an allocation scan yet.")
    return
  end

  emit(string.format(
    "AG Mall: %d malls, %d idle, %d assigned; %d shortages, %d craftable candidates, P=%d from %d request filters; scan age %d ticks%s",
    analysis.total_workshops or 0,
    analysis.idle_workshops or 0,
    analysis.assigned_workshops or 0,
    analysis.shortage_count or 0,
    analysis.candidate_count or 0,
    analysis.product_limit or C.DEFAULT_PRODUCT_LIMIT,
    analysis.request_count or 0,
    math.max(0, game.tick - (analysis.scan_tick or analysis.tick or game.tick)),
    analysis.skipped and " (" .. analysis.skipped .. ")" or ""
  ))

  for index, target in ipairs(analysis.targets or {}) do
    if index > target_limit then
      emit("AG Mall: additional shortages omitted.")
      break
    end

    local blocked = target.blocked_reason
        and ("; blocked=" .. target.blocked_reason
          .. (target.blocked_item and ":" .. target.blocked_item or ""))
        or ""
    emit(string.format(
      "%d. %s target=%d contents=%d incoming=%d missing=%d active=%d remaining=%d%s",
      index,
      Util.status_item_name(target.name, target.quality),
      target.target or 0,
      target.contents or 0,
      target.incoming or 0,
      target.missing or 0,
      target.active or 0,
      target.remaining_units or 0,
      blocked
    ))
  end

  for index, worker in ipairs(Brain.collect_worker_metrics(brain)) do
    if index > 20 then
      emit("AG Mall: additional workers omitted.")
      break
    end

    local target = worker.target
        and (" target=" .. Util.status_item_name(worker.target, worker.quality))
        or ""
    local waiting = worker.state == "waiting_inputs"
        and string.format(
          " present=%d incoming=%d%s",
          worker.present or 0,
          worker.incoming or 0,
          worker.missing and " missing=" .. worker.missing or ""
        )
        or ""
    emit(string.format(
      "mall %d state=%s%s replans=%d%s",
      worker.unit_number or 0,
      worker.state or "unknown",
      target,
      worker.replans or 0,
      waiting
    ))
  end
end

return M
