-- Logistic Nexus
-- Brain management: scheduling, candidate building, assessment.

local C = require("scripts.constants")
local Util = require("scripts.util")
local Storage = require("scripts.storage")
local Network = require("scripts.network")
local Construction = require("scripts.construction")
local Recipes = require("scripts.recipes")
local Planner = require("scripts.planner")
local Workshop = require("scripts.workshop")
local Status = require("scripts.status")
local Alerts = require("scripts.alerts")

local M = {}

------------------------------------------------------------
-- BRAIN MANAGEMENT
------------------------------------------------------------

function M.get_brain(network)
  Storage.init_brains()

  local key = Util.brain_key(network)
  local brain = storage.brains[key]

  if not brain then
    brain = {
      key = key,
      force_name = network.force.name,
      network_id = network.network_id,
      raw_supply_counts = {},
      recipe_choices = {},
      next_schedule_tick = 0
    }
    storage.brains[key] = brain
  end

  brain.network = network
  brain.workshops = brain.workshops or {}
  brain.raw_supply_counts = brain.raw_supply_counts or {}
  brain.recipe_choices = brain.recipe_choices or {}
  brain.next_schedule_tick = brain.next_schedule_tick or 0

  return brain
end

function M.reset_brain_runtime(brain)
  brain.workshops = {}
  brain.raw_supply_counts = {}
end

function M.clear_stale_recipe_cache(brain)
  for item_name, choice in pairs(brain.recipe_choices or {}) do
    if choice == false then
      brain.recipe_choices[item_name] = nil
    end
  end
end

------------------------------------------------------------
-- ACTIVE ASSIGNMENT COLLECTION
------------------------------------------------------------

function M.collect_active_assignments(brain)
  local machines = {}
  local outputs = {}

  for _, unit_number in pairs(brain.workshops or {}) do
    local workshop_data = storage.workshops[unit_number]
    local assignment = workshop_data and workshop_data.assignment

    if assignment
        and assignment.state ~= "draining"
        and assignment.item then
      local key = Util.item_key(assignment.item, assignment.quality or "normal")
      machines[key] = (machines[key] or 0) + 1
      outputs[key] = (outputs[key] or 0) + (assignment.expected_output or 1)
    end

    for _, queued in pairs(workshop_data and workshop_data.job_queue or {}) do
      if queued.target_item then
        local key = Util.item_key(queued.target_item, queued.target_quality or "normal")
        machines[key] = (machines[key] or 0) + 1
        outputs[key] = (outputs[key] or 0) + (queued.product_amount or 1)
      end
    end
  end

  return machines, outputs
end

------------------------------------------------------------
-- SCHEDULER CANDIDATES
------------------------------------------------------------

function M.candidate_choice_sort(a, b)
  local a_is_mall = not not C.WORKSHOP_NAMES[a.shortage.name]
  local b_is_mall = not not C.WORKSHOP_NAMES[b.shortage.name]

  if a_is_mall ~= b_is_mall then
    return a_is_mall
  end

  if a.machine_count ~= b.machine_count then
    return a.machine_count < b.machine_count
  end

  if a.remaining_units ~= b.remaining_units then
    return a.remaining_units > b.remaining_units
  end

  return a.shortage.name < b.shortage.name
end

function M.build_scheduler_candidates(brain, shortages, workshop, network)
  local active_machines, active_outputs = M.collect_active_assignments(brain)
  local candidates = {}

  for _, shortage in ipairs(shortages or {}) do
    local quality = shortage.quality or "normal"
    local key = Util.item_key(shortage.name, quality)
    local remaining_units = math.max(
      0,
      (shortage.missing or 0) - (active_outputs[key] or 0)
    )
    shortage.active_machines = active_machines[key] or 0
    shortage.active_output = active_outputs[key] or 0
    shortage.remaining_units = remaining_units

    if remaining_units > 0 then
      local recipe, product_amount = Recipes.cached_recipe_for_item(
        brain,
        workshop,
        network.force,
        shortage.name
      )

      if recipe and product_amount and product_amount > 0 then
        table.insert(candidates, {
          key = key,
          shortage = shortage,
          product_amount = product_amount,
          remaining_units = remaining_units,
          machine_count = active_machines[key] or 0,
          blocked_reason = nil
        })
      end
    end
  end

  return candidates
end

function M.choose_independent_job(brain, workshop_data, network, candidates, supply_budget)
  local skipped = {}
  local controls = Workshop.read_workshop_circuit_controls(workshop_data.entity)

  local setting_batches = 1
  local batch_setting = settings
      and settings.global
      and settings.global["logistic-nexus-max-batches-per-job"]
  if batch_setting and type(batch_setting.value) == "number" then
    setting_batches = math.floor(batch_setting.value)
  end
  if setting_batches < 1 then
    setting_batches = 1
  end

  while true do
    local window = {}

    for _, candidate in ipairs(candidates) do
      if candidate.remaining_units > 0
          and not skipped[candidate.key]
          and not controls.excluded_items[candidate.shortage.name] then
        table.insert(window, candidate)
        if #window >= controls.product_limit then
          break
        end
      end
    end

    if #window == 0 then
      return nil, nil
    end

    table.sort(window, M.candidate_choice_sort)
    local candidate = window[1]
    local product_amount = candidate.product_amount or 1
    local max_batches = math.min(
      setting_batches,
      math.ceil(candidate.remaining_units / product_amount)
    )
    local plan, blocked = Planner.build_candidate_plan(
      brain,
      workshop_data,
      network,
      candidate,
      supply_budget,
      max_batches
    )

    if plan then
      return plan, candidate
    end

    candidate.blocked_reason = blocked
    skipped[candidate.key] = true
  end
end

------------------------------------------------------------
-- WORKER METRICS
------------------------------------------------------------

function M.collect_worker_metrics(brain)
  local workers = {}

  for _, unit_number in ipairs(brain.workshops or {}) do
    local workshop_data = storage.workshops[unit_number]
    local assignment = workshop_data and workshop_data.assignment
    local metric = {
      unit_number = unit_number,
      state = assignment and assignment.state or "idle",
      target = assignment and assignment.item or nil,
      quality = assignment and assignment.quality or "normal",
      replans = assignment and assignment.replans or 0
    }

    if assignment and assignment.state == "waiting_inputs" then
      local requester = workshop_data.companions and workshop_data.companions.requester
      local present, incoming, uncovered = Workshop.assignment_delivery_progress(
        requester,
        assignment.requests
      )
      metric.present = present
      metric.incoming = incoming
      metric.missing = uncovered[1] and uncovered[1].name or nil
    end

    table.insert(workers, metric)
  end

  return workers
end

------------------------------------------------------------
-- BRAIN PROCESSING
------------------------------------------------------------

function M.process_brain(brain)
  local network = brain.network
  if not (network and network.valid) then
    return
  end

  local idle = {}
  local became_idle = false
  brain.preflight_supply_budget = {}

  for _, unit_number in pairs(brain.workshops or {}) do
    local workshop_data = storage.workshops[unit_number]
    local state = Workshop.tick_workshop_worker(workshop_data, brain)

    if state == "invalid" then
      storage.workshops[unit_number] = nil
    elseif workshop_data then
      if Workshop.can_accept_job(workshop_data) then
        table.insert(idle, workshop_data)
        if not workshop_data.could_accept_job then
          became_idle = true
        end
        workshop_data.could_accept_job = true
      else
        workshop_data.could_accept_job = false
      end
    end
  end

  if #idle == 0 then
    local previous = brain.last_analysis or {}
    brain.last_analysis = {
      tick = game.tick,
      total_workshops = #(brain.workshops or {}),
      idle_workshops = 0,
      assigned_workshops = 0,
      request_count = previous.request_count or 0,
      shortage_count = previous.shortage_count or 0,
      scan_tick = previous.scan_tick or previous.tick,
      skipped = "all-busy",
      targets = previous.targets or {},
      workers = previous.workers or {}
    }
    return
  end

  if not became_idle
      and not brain.schedule_dirty
      and game.tick < (brain.next_schedule_tick or 0) then
    return
  end

  brain.schedule_dirty = false
  brain.next_schedule_tick = game.tick + C.IDLE_RESCAN_INTERVAL
  brain.raw_supply_counts = {}
  -- Clear negative recipe cache entries so recipes enabled by scripts/mods
  -- since the last assessment can be discovered.
  M.clear_stale_recipe_cache(brain)
  local shortages, metrics = Construction.collect_prioritized_shortages(network)
  brain.metrics = metrics
  local representative = idle[1]
  local representative_controls = Workshop.read_workshop_circuit_controls(representative.entity)
  local candidates = M.build_scheduler_candidates(
    brain,
    shortages,
    representative.entity,
    network
  )
  local supply_budget = {}
  local assigned_count = 0

  for _, workshop_data in ipairs(idle) do
    local job, candidate = M.choose_independent_job(
      brain,
      workshop_data,
      network,
      candidates,
      supply_budget
    )

    if job then
      if Workshop.assign_job_to_workshop(workshop_data, job) then
        assigned_count = assigned_count + 1
        workshop_data.could_accept_job = false
        candidate.remaining_units = math.max(
          0,
          candidate.remaining_units - (job.product_amount or 1)
        )
        candidate.machine_count = candidate.machine_count + 1
        Planner.apply_supply_use(supply_budget, job.network_used)
      else
        Status.set_blocked_status(workshop_data.entity)
      end
    else
      Status.set_no_shortage_status(
        workshop_data.entity,
        brain.metrics and brain.metrics.request_count,
        brain.metrics and brain.metrics.shortage_count
      )
    end
  end

  local candidates_by_key = {}
  for _, candidate in ipairs(candidates) do
    candidates_by_key[candidate.key] = candidate
  end

  local target_metrics = {}
  local alert_workshop
  for _, unit_number in pairs(brain.workshops or {}) do
    local workshop_data = storage.workshops[unit_number]
    if workshop_data and workshop_data.entity and workshop_data.entity.valid then
      alert_workshop = workshop_data
      break
    end
  end

  for index, shortage in ipairs(shortages) do
    local candidate = candidates_by_key[Util.item_key(shortage.name, shortage.quality)]
    local blocked = candidate and candidate.blocked_reason
    local blocked_reason = blocked and blocked.reason or nil
    if not candidate and (shortage.remaining_units or 0) > 0 then
      blocked_reason = "uncraftable"
    end

    if blocked_reason and alert_workshop then
      Alerts.alert_blocked_item(
        brain,
        alert_workshop,
        Util.status_item_name(shortage.name, shortage.quality),
        blocked_reason,
        game.tick
      )
    end

    target_metrics[index] = {
      name = shortage.name,
      quality = shortage.quality or "normal",
      missing = shortage.missing or 0,
      available = shortage.available or 0,
      target = shortage.target or 0,
      contents = shortage.contents or 0,
      incoming = shortage.incoming or 0,
      construction_requested = shortage.construction_requested or 0,
      active = candidate and candidate.machine_count or shortage.active_machines or 0,
      remaining_units = candidate
          and candidate.remaining_units
          or shortage.remaining_units
          or 0,
      blocked_reason = blocked_reason,
      blocked_item = blocked and blocked.item or nil
    }
  end

  brain.last_analysis = {
    tick = game.tick,
    scan_tick = game.tick,
    total_workshops = #(brain.workshops or {}),
    idle_workshops = #idle,
    assigned_workshops = assigned_count,
    request_count = metrics.request_count or 0,
    shortage_count = metrics.shortage_count or 0,
    candidate_count = #candidates,
    product_limit = representative_controls.product_limit or C.DEFAULT_PRODUCT_LIMIT,
    targets = target_metrics,
    workers = M.collect_worker_metrics(brain)
  }
end

------------------------------------------------------------
-- ASSESS ALL WORKSHOPS
------------------------------------------------------------

function M.brain_assess_tick_offset(key)
  if not key or key == "" then
    return 0
  end

  local hash = 0
  for i = 1, #key do
    hash = (hash * 31 + string.byte(key, i)) % 1000000007
  end

  return hash % C.ASSESS_INTERVAL
end

function M.assess_all_workshops()
  Storage.init_storage()
  Storage.init_brains()
  Storage.preflight_replans_remaining = C.PREFLIGHT_REPLANS_PER_ASSESS

  for _, brain in pairs(storage.brains or {}) do
    M.reset_brain_runtime(brain)
    brain.network = nil
  end

  for unit_number, workshop_data in pairs(storage.workshops or {}) do
    local workshop = workshop_data and workshop_data.entity

    if not (workshop and workshop.valid) then
      storage.workshops[unit_number] = nil
    else
      local assignment = workshop_data.assignment
      if assignment and assignment.state ~= "draining" then
        Status.set_goal_sprite(
          workshop_data,
          assignment.item,
          assignment.recipe,
          assignment.quality
        )
      elseif workshop_data.goal_sprites
          or workshop_data.goal_map_display
          or workshop_data.goal_world_display then
        Status.destroy_goal_sprite(workshop_data)
      end

      local network = Network.get_network_for_workshop(workshop_data)

      if network and network.valid then
        local brain = M.get_brain(network)
        table.insert(brain.workshops, unit_number)
      else
        Workshop.clear_workshop_job(workshop_data, "no-network")
      end
    end
  end

  for key, brain in pairs(storage.brains or {}) do
    if brain.network and brain.workshops and #brain.workshops > 0 then
      M.process_brain(brain)
    else
      storage.brains[key] = nil
    end
  end
end

function M.process_due_brains()
  Storage.init_storage()
  Storage.preflight_replans_remaining = C.PREFLIGHT_REPLANS_PER_ASSESS

  local slot = game.tick % C.ASSESS_INTERVAL

  for key, brain in pairs(storage.brains or {}) do
    if M.brain_assess_tick_offset(key) == slot then
      if brain.network
          and brain.network.valid
          and brain.workshops
          and #brain.workshops > 0 then
        local ok, err = pcall(M.process_brain, brain)
        if not ok then
          log("Logistic Nexus process_brain error for " .. tostring(key) .. ": " .. tostring(err))
        end
      else
        storage.brains[key] = nil
      end
    end
  end
end

return M
