-- Logistic Nexus
-- Debug commands for diagnosing mall, construction, and status issues.

local C = require("scripts.constants")
local Util = require("scripts.util")
local Storage = require("scripts.storage")
local Network = require("scripts.network")
local Recipes = require("scripts.recipes")
local Planner = require("scripts.planner")
local Construction = require("scripts.construction")
local Brain = require("scripts.brain")

local M = {}

------------------------------------------------------------
-- WORKSHOP FINDER
------------------------------------------------------------

local function find_debug_workshop(player)
  local selected = player and player.selected
  if selected and selected.valid and C.WORKSHOP_NAMES[selected.name] and selected.unit_number then
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

------------------------------------------------------------
-- DEBUG: MALL ITEM
------------------------------------------------------------

function M.debug_mall_item(player, item_name)
  Storage.init_storage()

  local workshop_data = find_debug_workshop(player)
  if not workshop_data then
    player.print("Logistic Nexus debug: no Logistic Nexus workshop found for this force.")
    return
  end

  local network = Network.get_network_for_workshop(workshop_data)
  if not network then
    player.print("Logistic Nexus debug: selected Logistic Nexus is outside a logistic network.")
    return
  end

  local recipe = Recipes.find_recipe_for_item(workshop_data.entity, network.force, item_name)
  if not recipe then
    local source_recipe = network.force.recipes[item_name]
    local barrelled_recipe = network.force.recipes[C.BARRELLED_RECIPE_PREFIX .. item_name]

    player.print("Logistic Nexus debug: no enabled Logistic Nexus-compatible recipe for " .. item_name .. ".")
    if source_recipe then
      player.print(
        "Logistic Nexus debug: source recipe "
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
        player.print("Logistic Nexus debug: workshop crafting_categories: [" .. cat_str .. "]")
        if source_recipe.valid then
          local src_cat = source_recipe.category
          local src_cat_str = src_cat and tostring(src_cat) or ""
          player.print("Logistic Nexus debug: recipe category: [" .. src_cat_str .. "]")
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
          player.print("Logistic Nexus debug: recipe_has_supported_category=" .. tostring(has_cat))
          local pa = Recipes.recipe_product_amount(source_recipe, item_name)
          player.print("Logistic Nexus debug: recipe_product_amount=" .. tostring(pa))
          local ings = Recipes.recipe_item_ingredients(source_recipe)
          player.print("Logistic Nexus debug: recipe_item_ingredients=" .. tostring(ings and #ings or "nil"))
          player.print("Logistic Nexus debug: recipe.products count=" .. tostring(#(source_recipe.products or {})))
          for _, p in pairs(source_recipe.products or {}) do
            player.print("Logistic Nexus debug:   product: type=" .. tostring(p.type) .. " name=" .. tostring(p.name) .. " amount=" .. tostring(p.amount) .. " amount_min=" .. tostring(p.amount_min) .. " amount_max=" .. tostring(p.amount_max) .. " probability=" .. tostring(p.probability))
          end
        end
      end
    end
    if barrelled_recipe then
      player.print(
        "Logistic Nexus debug: barrelled recipe "
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

  -- Build a full internal craft plan and trace the path to show where/why it
  -- would be skipped.
  local trace = {}
  local debug_brain = {
    force_name = network.force.name,
    recipe_choices = {},
    raw_supply_counts = {}
  }
  local plan, blocked = Planner.build_internal_craft_plan(
    workshop_data.entity,
    network,
    item_name,
    "normal",
    debug_brain,
    {trace = trace}
  )

  player.print("Logistic Nexus debug: craft trace for " .. item_name)
  for _, line in ipairs(trace) do
    player.print("Logistic Nexus debug: " .. line)
  end

  if not plan then
    player.print(
      "Logistic Nexus debug: PLAN BLOCKED - "
          .. (blocked.reason or "unknown")
          .. " at "
          .. (blocked.item or item_name)
          .. "."
    )
  else
    player.print(
      "Logistic Nexus debug: plan OK - "
          .. #plan.steps
          .. " crafting step(s), recipe: "
          .. recipe.name
          .. "."
    )
    for _, request in ipairs(plan.requests or {}) do
      player.print(
        "Logistic Nexus debug: request from network: "
            .. request.name
            .. " x"
            .. request.amount
            .. "."
      )
    end
  end
end

------------------------------------------------------------
-- DEBUG: CONSTRUCTION ITEM
------------------------------------------------------------

function M.debug_construction_item(player, item_name)
  Storage.init_storage()

  if not (player and item_name and item_name ~= "") then
    return
  end

  local network
  local selected = player.selected
  if selected and selected.valid and C.WORKSHOP_NAMES[selected.name] then
    local workshop_data = selected.unit_number and storage.workshops[selected.unit_number]
    network = workshop_data and Network.get_network_for_workshop(workshop_data)
  end

  if not (network and network.valid) then
    network = player.surface.find_logistic_network_by_position(player.position, player.force)
  end

  if not (network and network.valid) then
    player.print("Logistic Nexus construction debug: no logistic network at player or selected Logistic Nexus.")
    return
  end

  local surface, blocks = Construction.construction_scan_blocks(network)
  if not (surface and blocks and #blocks > 0) then
    player.print("Logistic Nexus construction debug: selected network has no construction scan area.")
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
    "Logistic Nexus construction debug: %s scanned=%d matching=%d registered=%d in-network=%d counted-ghosts=%d counted-items=%d reserved=%d net=%s.",
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
    player.print("Logistic Nexus construction debug: " .. sample)
  end
end

------------------------------------------------------------
-- DEBUG: STATUS
------------------------------------------------------------

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
  if selected and selected.valid and C.WORKSHOP_NAMES[selected.name] then
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
    emit("Logistic Nexus: no logistic network at the player or selected mall.")
    return
  end

  local brain = storage.brains and storage.brains[Util.brain_key(network)]
  local analysis = brain and brain.last_analysis
  if not analysis then
    emit("Logistic Nexus: this network has not completed an allocation scan yet.")
    return
  end

  emit(string.format(
    "Logistic Nexus: %d malls, %d idle, %d assigned; %d shortages, %d craftable candidates, P=%d from %d request filters; scan age %d ticks%s",
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
      emit("Logistic Nexus: additional shortages omitted.")
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
      emit("Logistic Nexus: additional workers omitted.")
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
