-- Logistic Nexus
-- Workshop assignment lifecycle, internal inventory, and worker ticking.

local C = require("scripts.constants")
local Util = require("scripts.util")
local Status = require("scripts.status")
local Companions = require("scripts.companions")
local Construction = require("scripts.construction")
local Planner = require("scripts.planner")
local Network = require("scripts.network")

local M = {}

-- Debug logging: controlled by the 'logistic-nexus-debug-logging' setting.
-- When enabled, logs every state transition and item movement to factorio-current.log.
local function debug_enabled_check()
  return settings and settings.global
    and settings.global["logistic-nexus-debug-logging"]
    and settings.global["logistic-nexus-debug-logging"].value
end

local function dbg(workshop_data, assignment, msg)
  if not debug_enabled_check() then return end
  local ws = workshop_data and workshop_data.entity
  if not (ws and ws.valid) then return end

  local output_count = 0
  local output_inv = ws.get_output_inventory()
  if output_inv and output_inv.valid then
    for _, item in pairs(output_inv.get_contents() or {}) do
      output_count = output_count + (item.count or 0)
    end
  end

  local internal_count = 0
  local internal_items = ""
  if assignment and assignment.internal_inventory then
    for key, count in pairs(assignment.internal_inventory) do
      if count > 0 then
        internal_count = internal_count + count
        internal_items = internal_items .. key .. "=" .. count .. " "
      end
    end
  end

  local recipe_name = "nil"
  local r = ws.get_recipe()
  if r then recipe_name = r.name end

  local msg_line = string.format(
    "[LN-DBG] tick=%d unit=%d state=%s item=%s recipe=%s step=%d/%d progress=%.3f finished=%d output=%d internal=%d [%s] | %s",
    game.tick,
    ws.unit_number or 0,
    (assignment and assignment.state) or "nil",
    (assignment and assignment.item) or "nil",
    recipe_name,
    (assignment and assignment.current_step_index) or 0,
    (assignment and assignment.steps and #assignment.steps) or 0,
    ws.crafting_progress or 0,
    ws.products_finished or 0,
    output_count,
    internal_count,
    internal_items,
    msg or ""
  )
  log(msg_line)
  print(msg_line)
end

-- Export dbg so other functions can use it
M.dbg = dbg

------------------------------------------------------------
-- STATE MACHINE
------------------------------------------------------------

-- All valid state transitions. If a transition isn't listed here,
-- it's a bug. Read this table to understand the state graph.
local VALID_TRANSITIONS = {
  waiting_inputs  = { settling_inputs = true },
  settling_inputs = { waiting_inputs = true, crafting_step = true, draining = true },
  crafting_step   = { crafting_step = true, waiting_inputs = true, draining = true },
  draining        = {},
}

local function transition_state(assignment, new_state)
  local allowed = VALID_TRANSITIONS[assignment.state]
  if not allowed or not allowed[new_state] then
    error("invalid state transition: " .. (assignment.state or "nil") .. " -> " .. new_state)
  end
  assignment.state = new_state
end

------------------------------------------------------------
-- OUTPUT CONTAINER OPERATIONS
------------------------------------------------------------

function M.insert_into_output_containers(workshop_data, item)
  if not (item and item.name and item.count and item.count > 0) then
    return nil
  end

  local provider = workshop_data.companions and workshop_data.companions.provider
  local remaining = Util.stack_definition(item.name, item.count, item.quality)

  if provider and provider.valid then
    local inserted = provider.insert(remaining)
    remaining.count = remaining.count - inserted
  end

  if remaining.count <= 0 then
    return nil
  end

  return remaining
end

function M.insert_or_spill_item(workshop_data, item, allow_spill)
  local remaining = M.insert_into_output_containers(workshop_data, item)
  if not remaining then
    return true
  end

  if allow_spill == false then
    return false
  end

  local provider = workshop_data.companions and workshop_data.companions.provider
  local workshop = workshop_data.entity
  local spill_target = (provider and provider.valid and provider) or workshop
  if spill_target and spill_target.valid then
    local ok = pcall(function()
      spill_target.surface.spill_item_stack({
        position = spill_target.position,
        stack = remaining,
        enable_looted = false,
        allow_belts = false,
        use_start_position_on_failure = true
      })
    end)

    if ok then
      return true
    end
  end

  return false
end

function M.insert_returned_items(workshop_data, items)
  if not items then
    return
  end

  for _, item in pairs(items) do
    M.insert_or_spill_item(workshop_data, item)
  end
end

function M.output_inventory_has_items(workshop)
  if not (workshop and workshop.valid and workshop.get_output_inventory) then
    return false
  end

  local inventory = workshop.get_output_inventory()
  if not inventory then
    return false
  end

  if inventory.is_empty then
    return not inventory.is_empty()
  end

  for _, item in pairs(inventory.get_contents() or {}) do
    if item.count and item.count > 0 then
      return true
    end
  end

  return false
end

function M.workshop_is_clear_for_reassessment(workshop_data)
  local workshop = workshop_data.entity

  if workshop.crafting_progress and workshop.crafting_progress > 0 then
    return false
  end

  if M.output_inventory_has_items(workshop) then
    return false
  end

  return true
end

------------------------------------------------------------
-- INTERNAL INVENTORY
------------------------------------------------------------

function M.requester_item_count(requester, name, quality)
  return Network.get_item_count_from_inventory(
    requester,
    defines.inventory.chest,
    Util.item_id(name, quality)
  )
end

local function internal_add(inventory, name, amount, quality)
  if not (name and amount and amount > 0) then
    return
  end

  local key = Util.item_key(name, quality)
  inventory[key] = (inventory[key] or 0) + amount
end

local function internal_remove(inventory, name, amount, quality)
  if not (name and amount and amount > 0) then
    return true
  end
  local key = Util.item_key(name, quality)

  if (inventory[key] or 0) < amount then
    return false
  end

  inventory[key] = inventory[key] - amount
  if inventory[key] <= 0 then
    inventory[key] = nil
  end

  return true
end

local function internal_count(inventory, name, quality)
  return inventory and inventory[Util.item_key(name, quality)] or 0
end

function M.move_requester_to_internal(workshop_data, assignment)
  local requester = workshop_data.companions and workshop_data.companions.requester
  local inventory = requester and requester.valid and requester.get_inventory(defines.inventory.chest)
  if not (inventory and inventory.valid) then
    return false
  end

  assignment.internal_inventory = assignment.internal_inventory or {}

  for _, item in pairs(inventory.get_contents() or {}) do
    local name = item.name
    local count = item.count or 0
    local quality = Util.quality_name(item.quality)

    if name and count > 0 then
      local removed = inventory.remove({
        name = name,
        count = count,
        quality = quality
      })

      if removed > 0 then
        internal_add(assignment.internal_inventory, name, removed, quality)
      end
    end
  end

  return inventory.is_empty()
end

function M.insert_internal_to_workshop(workshop_data, assignment, ingredients)
  local workshop = workshop_data.entity
  local internal = assignment.internal_inventory or {}

  if not (workshop and workshop.valid) then
    return false
  end

  for _, ingredient in pairs(ingredients or {}) do
    local amount = Util.ingredient_count(ingredient)
    if not amount then
      return false
    end

    if internal_count(internal, ingredient.name, ingredient.quality) < amount then
      return false
    end
  end

  for _, ingredient in pairs(ingredients or {}) do
    local amount = Util.ingredient_count(ingredient)
    if not amount then
      return false
    end
    local inserted = workshop.insert({
      name = ingredient.name,
      count = amount,
      quality = ingredient.quality or "normal"
    })

    if inserted ~= amount then
      if inserted > 0 then
        internal_remove(
          internal,
          ingredient.name,
          inserted,
          ingredient.quality
        )
      end
      return false
    end

    internal_remove(internal, ingredient.name, amount, ingredient.quality)
  end

  return true
end

function M.collect_workshop_output_to_internal(workshop_data, assignment)
  local workshop = workshop_data and workshop_data.entity
  local inventory = workshop and workshop.valid and workshop.get_output_inventory()

  if not (inventory and inventory.valid) then
    return true
  end

  assignment.internal_inventory = assignment.internal_inventory or {}

  for _, item in pairs(inventory.get_contents() or {}) do
    local name = item.name
    local count = item.count or 0
    local quality = Util.quality_name(item.quality)

    if name and count > 0 then
      local removed = inventory.remove({
        name = name,
        count = count,
        quality = quality
      })

      if removed > 0 then
        internal_add(assignment.internal_inventory, name, removed, quality)
      end
    end
  end

  return inventory.is_empty()
end

function M.output_internal_inventory(workshop_data, assignment)
  local internal = assignment.internal_inventory or {}
  local leftovers = {}

  for key, count in pairs(internal) do
    if count > 0 then
      local name, quality = Util.split_item_key(key)
      table.insert(leftovers, {
        name = name,
        quality = quality,
        count = count
      })
    end
  end

  M.insert_returned_items(workshop_data, leftovers)
  assignment.internal_inventory = {}
  dbg(workshop_data, assignment, "output_internal_inventory: pushed " .. #leftovers .. " item types to provider")
end

function M.requester_has_exact_ingredients(requester, ingredients)
  if not (requester and requester.valid) then
    return false
  end

  local needed = {}
  for _, ingredient in pairs(ingredients or {}) do
    local amount = Util.ingredient_count(ingredient)
    if not amount then
      return false
    end
    local key = Util.item_key(ingredient.name, ingredient.quality)
    needed[key] = (needed[key] or 0) + amount
  end

  local inventory = requester.get_inventory(defines.inventory.chest)
  if not (inventory and inventory.valid) then
    return false
  end

  local actual = {}
  for _, item in pairs(inventory.get_contents() or {}) do
    if item.name and (item.count or 0) > 0 then
      local quality = Util.quality_name(item.quality)
      local key = Util.item_key(item.name, quality)
      actual[key] = (actual[key] or 0) + (item.count or 0)
    end
  end

  for key, amount in pairs(needed) do
    if (actual[key] or 0) ~= amount then
      return false
    end
  end

  for key, count in pairs(actual) do
    if count > 0 and not needed[key] then
      return false
    end
  end

  return true
end

function M.requester_has_required_ingredients(requester, ingredients)
  if not (requester and requester.valid) then
    return false
  end

  local needed = {}
  for _, ingredient in pairs(ingredients or {}) do
    local amount = Util.ingredient_count(ingredient)
    if not amount then
      return false
    end
    local key = Util.item_key(ingredient.name, ingredient.quality)
    needed[key] = (needed[key] or 0) + amount
  end

  local inventory = requester.get_inventory(defines.inventory.chest)
  if not (inventory and inventory.valid) then
    return false
  end

  local actual = {}
  for _, item in pairs(inventory.get_contents() or {}) do
    if item.name and (item.count or 0) > 0 then
      local quality = Util.quality_name(item.quality)
      local key = Util.item_key(item.name, quality)
      actual[key] = (actual[key] or 0) + (item.count or 0)
    end
  end

  for key, amount in pairs(needed) do
    if (actual[key] or 0) < amount then
      return false
    end
  end

  return true
end

------------------------------------------------------------
-- RECIPE / JOB MANAGEMENT
------------------------------------------------------------

local function is_module_item(item)
  local proto = prototypes.item[item.name]
  return proto and proto.type == "module"
end

local function insert_modules_into_workshop(workshop, items)
  if not (workshop and workshop.valid and workshop.get_inventory) then
    return items
  end

  local ok, module_inventory = pcall(function()
    return workshop.get_inventory(defines.inventory.crafter_modules)
  end)

  if not ok or not (module_inventory and module_inventory.valid) then
    return items
  end

  local leftovers = {}
  for _, item in pairs(items or {}) do
    if is_module_item(item) then
      local inserted = module_inventory:insert({
        name = item.name,
        count = item.count or 1,
        quality = item.quality or "normal"
      })
      if inserted < (item.count or 1) then
        item.count = (item.count or 1) - inserted
        table.insert(leftovers, item)
      end
    else
      table.insert(leftovers, item)
    end
  end

  return leftovers
end

function M.set_workshop_recipe(workshop_data, recipe, quality)
  local workshop = workshop_data.entity
  if not (workshop and workshop.valid) then
    return false
  end
  quality = Util.quality_name(quality)

  local current_recipe, current_quality = workshop.get_recipe()
  if current_recipe
      and recipe
      and current_recipe.name == recipe.name
      and Util.quality_name(current_quality) == quality then
    return true
  end

  local ok, returned_items = pcall(function()
    return workshop.set_recipe(recipe and recipe.name or nil, recipe and quality or nil)
  end)

  if ok then
    local non_modules = insert_modules_into_workshop(workshop, returned_items)
    M.insert_returned_items(workshop_data, non_modules)
    workshop_data.current_recipe = recipe and recipe.name or nil
    workshop_data.current_recipe_quality = recipe and quality or nil
    return true
  end

  return false
end

function M.clear_workshop_job(workshop_data, status, metrics)
  local workshop = workshop_data.entity
  local requester = workshop_data.companions and workshop_data.companions.requester
  local assignment = workshop_data.assignment

  if assignment and assignment.internal_inventory then
    M.output_internal_inventory(workshop_data, assignment)
  end

  M.set_workshop_recipe(workshop_data, nil)

  if requester and requester.valid then
    Companions.clear_requester_requests(requester)
  end

  workshop_data.current_item = nil
  workshop_data.current_quality = nil
  workshop_data.current_shortage = 0
  workshop_data.current_recipe = nil
  workshop_data.current_recipe_quality = nil
  workshop_data.last_products_finished = workshop.products_finished or 0
  workshop_data.recorded_products_finished = workshop.products_finished or 0
  workshop_data.current_product_amount = nil
  workshop_data.current_is_construction = nil
  workshop_data.current_construction_target = 0
  workshop_data.current_construction_reserved = 0
  workshop_data.waiting_for_clear = nil
  Status.destroy_goal_sprite(workshop_data)

  if status == "no-network" then
    Status.set_no_network_status(workshop)
  else
    Status.set_no_shortage_status(
      workshop,
      metrics and metrics.request_count,
      metrics and metrics.shortage_count
    )
  end
end

function M.reset_workshop_assignment(workshop_data)
  local requester = workshop_data.companions and workshop_data.companions.requester
  if requester and requester.valid then
    Companions.clear_requester_requests(requester)
  end

  workshop_data.assignment = nil
  workshop_data.current_item = nil
  workshop_data.current_quality = nil
  workshop_data.current_shortage = 0
  workshop_data.current_recipe = nil
  workshop_data.current_recipe_quality = nil
  workshop_data.current_product_amount = nil
  workshop_data.current_is_construction = nil
  workshop_data.current_construction_target = 0
  workshop_data.current_construction_reserved = 0
  workshop_data.waiting_for_clear = nil
  Status.destroy_goal_sprite(workshop_data)
end

function M.can_accept_job(workshop_data)
  if not (workshop_data and workshop_data.entity and workshop_data.entity.valid) then
    return false
  end

  local queue = workshop_data.job_queue or {}
  return #queue < C.WORKSHOP_QUEUE_SIZE
end

function M.start_job_now(workshop_data, job)
  local requester = workshop_data.companions and workshop_data.companions.requester

  if not M.set_workshop_recipe(workshop_data, nil) then
    return false
  end

  if not Companions.set_requester_requests(requester, job.requests or {}) then
    return false
  end

  local workshop = workshop_data.entity
  local expected_output = job.target_output_amount or job.product_amount or 1

  workshop_data.assignment = {
    state = "waiting_inputs",
    item = job.target_item or job.name,
    quality = job.target_quality or job.quality or "normal",
    recipe = job.target_recipe,
    requests = job.requests or {},
    ingredients = job.requests or {},
    steps = job.steps or {},
    current_step_index = 0,
    internal_inventory = {},
    expected_output = expected_output,
    product_amount = expected_output,
    batch_count = job.batch_count or 1,
    plan_name = job.plan_name or job.name,
    plan_quality = job.plan_quality or job.quality or "normal",
    plan_priority = job.plan_priority or 1,
    construction_requested = job.construction_requested or 0,
    preflight_replanned = false,
    last_progress_tick = game.tick,
    last_crafting_progress = 0,
    crafting_stall_tick = game.tick,
    last_present_count = 0,
    last_incoming_count = 0,
    baseline_products_finished = workshop.products_finished or 0,
    recorded_products_finished = workshop.products_finished or 0
  }

  workshop_data.current_item = job.target_item or job.name
  workshop_data.current_quality = job.target_quality or job.quality or "normal"
  workshop_data.current_recipe = nil
  workshop_data.current_product_amount = expected_output
  workshop_data.current_is_construction = (job.construction_requested or 0) > 0
  workshop_data.current_construction_target = job.construction_requested or 0
  workshop_data.current_construction_reserved = 0
  Status.set_goal_sprite(
    workshop_data,
    job.target_item or job.name,
    job.target_recipe,
    job.target_quality or job.quality
  )
  Status.set_finishing_status(workshop, job.target_item or job.name)

  return true
end

function M.assign_job_to_workshop(workshop_data, job)
  if not M.can_accept_job(workshop_data) then
    return false
  end

  if workshop_data.assignment then
    workshop_data.job_queue = workshop_data.job_queue or {}
    table.insert(workshop_data.job_queue, job)
    return true
  end

  return M.start_job_now(workshop_data, job)
end

function M.queue_job(workshop_data, job)
  return M.assign_job_to_workshop(workshop_data, job)
end

------------------------------------------------------------
-- ASSIGNMENT PROGRESS / REPLAN
------------------------------------------------------------

function M.assignment_delivery_progress(requester, ingredients)
  local point = Network.get_requester_point(requester)
  local present = 0
  local incoming = 0
  local uncovered = {}

  for _, ingredient in pairs(ingredients or {}) do
    local required = Util.ingredient_count(ingredient)
    if not required then
      table.insert(uncovered, {
        name = ingredient.name,
        quality = ingredient.quality or "normal",
        amount = 1
      })
      return present, incoming, uncovered
    end
    local quality = ingredient.quality or "normal"
    local in_chest = M.requester_item_count(requester, ingredient.name, quality)
    local on_the_way = Network.targeted_delivery_count(
      point,
      ingredient.name,
      quality
    )
    present = present + math.min(required, in_chest)
    incoming = incoming + math.min(math.max(0, required - in_chest), on_the_way)

    if in_chest + on_the_way < required then
      table.insert(uncovered, {
        name = ingredient.name,
        quality = quality,
        amount = required - in_chest - on_the_way
      })
    end
  end

  return present, incoming, uncovered
end

function M.replan_waiting_assignment(
    workshop_data,
    assignment,
    brain,
    supply_budget
  )
  local requester = workshop_data.companions and workshop_data.companions.requester
  local network = brain and brain.network
  if not (requester and requester.valid and network and network.valid) then
    return false, {reason = "no-network"}
  end

  brain.raw_supply_counts = {}
  local plan, blocked = Planner.build_internal_craft_plan(
    workshop_data.entity,
    network,
    assignment.item,
    assignment.quality or "normal",
    brain,
    {
      local_counts = Network.requester_planning_counts(requester, true),
      supply_budget = supply_budget,
      max_batches = assignment.batch_count or 1
    }
  )

  if not plan then
    return false, blocked
  end

  if not Companions.set_requester_requests(requester, plan.requests or {}) then
    return false, {reason = "request-update-failed"}
  end

  if supply_budget then
    Planner.apply_supply_use(supply_budget, plan.network_used)
  end

  assignment.requests = plan.requests or {}
  assignment.ingredients = assignment.requests
  assignment.steps = plan.steps or {}
  assignment.current_step_index = 0
  assignment.current_step = nil
  assignment.last_progress_tick = game.tick
  assignment.last_present_count = 0
  assignment.last_incoming_count = 0
  assignment.preflight_replanned = false
  assignment.replans = (assignment.replans or 0) + 1
  workshop_data.current_recipe = nil
  Status.set_finishing_status(workshop_data.entity, assignment.item)
  return true, nil
end

function M.abandon_waiting_assignment(workshop_data, assignment, blocked)
  dbg(workshop_data, assignment, "ABANDON: " .. (blocked and blocked.reason or "unknown") .. " item=" .. (blocked and blocked.item or "?"))
  local requester = workshop_data.companions and workshop_data.companions.requester
  if requester and requester.valid then
    Companions.clear_requester_requests(requester)
  end

  -- Collect any items still in the workshop's output inventory before
  -- abandoning. Without this, crafted items can be stranded in the
  -- assembling machine's output slot when the assignment is abandoned
  -- mid-craft (e.g. crafting-stall detection).
  if assignment then
    M.collect_workshop_output_to_internal(workshop_data, assignment)
    if assignment.internal_inventory then
      M.output_internal_inventory(workshop_data, assignment)
    end
  end

  workshop_data.last_blocked_reason = blocked and blocked.reason or "missing-material"
  workshop_data.last_blocked_item = blocked and blocked.item or nil
  workshop_data.last_blocked_tick = game.tick
  M.reset_workshop_assignment(workshop_data)
  Status.set_idle_status(workshop_data.entity)
end

function M.refresh_assignment_plan_from_internal(
    workshop_data,
    assignment,
    brain
  )
  local requester = workshop_data.companions and workshop_data.companions.requester
  local network = brain and brain.network

  if not (requester and requester.valid and network and network.valid) then
    return false, {reason = "no-network"}
  end

  brain.raw_supply_counts = {}
  local plan, blocked = Planner.build_internal_craft_plan(
    workshop_data.entity,
    network,
    assignment.item,
    assignment.quality or "normal",
    brain,
    {
      local_counts = Network.requester_planning_counts(requester, true),
      internal_counts = assignment.internal_inventory,
      max_batches = assignment.batch_count or 1
    }
  )

  if not plan then
    return false, blocked
  end

  if not Companions.set_requester_requests(requester, plan.requests or {}) then
    return false, {reason = "request-update-failed"}
  end

  assignment.requests = plan.requests or {}
  assignment.ingredients = assignment.requests
  assignment.steps = plan.steps or {}
  assignment.current_step_index = 0
  assignment.current_step = nil
  assignment.last_progress_tick = game.tick
  assignment.last_present_count = 0
  assignment.last_incoming_count = 0
  assignment.preflight_replanned = true
  assignment.replans = (assignment.replans or 0) + 1
  workshop_data.current_recipe = nil

  if #(assignment.requests or {}) > 0 then
    transition_state(assignment, "waiting_inputs")
    Status.set_finishing_status(workshop_data.entity, assignment.item)
    return "waiting", nil
  end

  return true, nil
end

function M.start_next_internal_step(workshop_data, assignment)
  local workshop = workshop_data.entity
  local next_index = (assignment.current_step_index or 0) + 1
  local step = assignment.steps and assignment.steps[next_index]

  if not step then
    dbg(workshop_data, assignment, "no more steps -> draining")
    workshop_data.current_item = assignment.item
    workshop_data.current_quality = assignment.quality or "normal"
    workshop_data.current_is_construction = (assignment.construction_requested or 0) > 0
    Construction.reserve_construction_output(workshop_data, assignment.product_amount or 1)
    M.output_internal_inventory(workshop_data, assignment)
    M.set_workshop_recipe(workshop_data, nil)
    Status.destroy_goal_sprite(workshop_data)
    transition_state(assignment, "draining")
    Status.set_finishing_status(workshop, assignment.item)
    return true
  end

  dbg(workshop_data, assignment, "start step " .. next_index .. ": " .. (step.recipe_name or "?"))
  if not M.set_workshop_recipe(workshop_data, step.recipe, step.quality) then
    dbg(workshop_data, assignment, "set_recipe FAILED")
    return false
  end

  if not M.insert_internal_to_workshop(workshop_data, assignment, step.ingredients) then
    return false
  end

  assignment.current_step_index = next_index
  assignment.current_step = step
  transition_state(assignment, "crafting_step")
  assignment.baseline_products_finished = workshop.products_finished or 0
  assignment.recorded_products_finished = workshop.products_finished or 0
  assignment.step_target_finished = (workshop.products_finished or 0) + (step.crafts or 1)
  -- Reset stall tracking for the new step
  assignment.last_step_check = next_index
  assignment.step_stall_tick = game.tick
  workshop_data.current_recipe = step.recipe_name
  Status.set_working_status(workshop, assignment.item, next_index)
  return true
end

function M.continue_assignment_after_internal_change(
    workshop_data,
    assignment,
    brain
  )
  if (assignment.current_step_index or 0) < #(assignment.steps or {}) then
    dbg(workshop_data, assignment, "more steps remain, refreshing plan")
    local refreshed, blocked = M.refresh_assignment_plan_from_internal(
      workshop_data,
      assignment,
      brain
    )

    if refreshed == "waiting" then
      dbg(workshop_data, assignment, "refresh returned waiting")
      return true
    end

    if not refreshed then
      dbg(workshop_data, assignment, "refresh FAILED, abandoning")
      M.abandon_waiting_assignment(workshop_data, assignment, blocked)
      return false
    end
  end

  dbg(workshop_data, assignment, "calling start_next_internal_step")
  return M.start_next_internal_step(workshop_data, assignment)
end

------------------------------------------------------------
-- STATE HANDLERS
-- Each handler processes one assignment.state and returns
-- "idle", "working", or "invalid".
------------------------------------------------------------

local tick_waiting_inputs
local tick_settling_inputs
local tick_crafting_step
local tick_draining

local STATE_HANDLERS = {
  waiting_inputs  = function(...) return tick_waiting_inputs(...) end,
  settling_inputs = function(...) return tick_settling_inputs(...) end,
  crafting_step   = function(...) return tick_crafting_step(...) end,
  draining        = function(...) return tick_draining(...) end,
}

function tick_waiting_inputs(workshop_data, assignment, brain)
  local workshop = workshop_data.entity
  local requester = workshop_data.companions.requester

  assignment.last_progress_tick = assignment.last_progress_tick or game.tick
  assignment.last_present_count = assignment.last_present_count or 0
  assignment.last_incoming_count = assignment.last_incoming_count or 0

  if M.requester_has_exact_ingredients(requester, assignment.requests) then
    if not assignment.preflight_replanned then
      local replanned, blocked = M.replan_waiting_assignment(
        workshop_data,
        assignment,
        brain,
        brain.preflight_supply_budget
      )

      if not replanned then
        M.abandon_waiting_assignment(workshop_data, assignment, blocked)
        return "idle"
      end

      assignment.preflight_replanned = true
    end

    if M.requester_has_required_ingredients(requester, assignment.requests) then
      transition_state(assignment, "settling_inputs")
      assignment.settle_until = game.tick + C.REQUEST_SETTLE_TICKS
    end
    Status.set_finishing_status(workshop, assignment.item)
  else
    if M.requester_has_required_ingredients(requester, assignment.requests) then
      -- All required items are present in the requester (extras are okay;
      -- they will be moved to internal inventory and returned later).
      transition_state(assignment, "settling_inputs")
      assignment.settle_until = game.tick + C.REQUEST_SETTLE_TICKS
    else
      local present, incoming, uncovered = M.assignment_delivery_progress(
        requester,
        assignment.requests
      )

      if present > (assignment.last_present_count or 0)
          or incoming > (assignment.last_incoming_count or 0) then
        assignment.last_progress_tick = game.tick
      end

      assignment.last_present_count = present
      assignment.last_incoming_count = incoming

      local stalled = game.tick - (assignment.last_progress_tick or game.tick)
          >= C.WAITING_INPUT_RECHECK_TICKS

      if stalled then
        if #uncovered == 0 then
          -- Required items are covered by incoming deliveries; keep waiting.
          assignment.last_progress_tick = game.tick
        else
          local replanned, blocked = M.replan_waiting_assignment(
            workshop_data,
            assignment,
            brain
          )

          if not replanned then
            M.abandon_waiting_assignment(workshop_data, assignment, blocked)
            return "idle"
          end
        end
      end
    end

    Status.set_finishing_status(workshop, assignment.item)
  end

  return "working"
end

function tick_settling_inputs(workshop_data, assignment, brain)
  local workshop = workshop_data.entity
  local requester = workshop_data.companions.requester

  if not M.requester_has_required_ingredients(requester, assignment.requests) then
    transition_state(assignment, "waiting_inputs")
    assignment.settle_until = nil
    Status.set_finishing_status(workshop, assignment.item)
    return "working"
  end

  if game.tick >= (assignment.settle_until or game.tick) then
    Companions.freeze_requester_batch(requester)
    if M.move_requester_to_internal(workshop_data, assignment)
        and M.continue_assignment_after_internal_change(
          workshop_data,
          assignment,
          brain
        ) then
      Status.set_working_status(workshop, assignment.item, assignment.current_step_index or 1)
    else
      Status.set_blocked_status(workshop)
    end
  else
    Status.set_finishing_status(workshop, assignment.item)
  end

  return "working"
end

function tick_crafting_step(workshop_data, assignment, brain)
  local workshop = workshop_data.entity
  local current_finished = workshop.products_finished or 0
  local recorded_finished = assignment.recorded_products_finished
      or assignment.baseline_products_finished or 0
  local step_target = assignment.step_target_finished or (recorded_finished + 1)

  if current_finished >= step_target then
    dbg(workshop_data, assignment, "step complete: finished=" .. current_finished .. " target=" .. step_target)
    assignment.recorded_products_finished = current_finished

    if M.collect_workshop_output_to_internal(workshop_data, assignment)
        and M.continue_assignment_after_internal_change(
          workshop_data,
          assignment,
          brain
        ) then
      Status.set_working_status(workshop, assignment.item, assignment.current_step_index or 1)
    else
      Status.set_blocked_status(workshop)
    end
    return "working"
  end

  -- Stall detection: if the step index hasn't advanced for a while,
  -- the workshop is stuck producing intermediate items without
  -- completing the final product. This happens when supply fluctuates
  -- and the workshop keeps crafting partial intermediates.
  local CRAFTING_STALL_TICKS = 2400  -- 40 seconds at normal speed
  local current_step = assignment.current_step_index or 0
  assignment.last_step_check = assignment.last_step_check or current_step
  assignment.step_stall_tick = assignment.step_stall_tick or game.tick

  if current_step ~= assignment.last_step_check then
    assignment.last_step_check = current_step
    assignment.step_stall_tick = game.tick
  elseif game.tick - assignment.step_stall_tick >= CRAFTING_STALL_TICKS then
    dbg(workshop_data, assignment, "STALL DETECTED: step=" .. current_step .. " stall_ticks=" .. (game.tick - assignment.step_stall_tick))
    M.abandon_waiting_assignment(workshop_data, assignment, {reason = "crafting-stall", item = assignment.item})
    return "idle"
  end

  Status.set_working_status(workshop, assignment.item, assignment.current_step_index or 1)
  return "working"
end

function tick_draining(workshop_data, assignment, brain)
  local workshop = workshop_data.entity
  dbg(workshop_data, assignment, "draining tick")

  -- Move any items from the workshop's output inventory to the provider.
  -- Also flush internal_inventory — items may have been collected from
  -- a prior crafting step but not yet output to the provider.
  if not (workshop.crafting_progress and workshop.crafting_progress > 0) then
    M.collect_workshop_output_to_internal(workshop_data, assignment)
    local internal = assignment.internal_inventory or {}
    local has_internal = false
    for _, count in pairs(internal) do
      if count > 0 then has_internal = true; break end
    end
    if has_internal then
      M.output_internal_inventory(workshop_data, assignment)
    end
  end

  if M.workshop_is_clear_for_reassessment(workshop_data) then
    M.reset_workshop_assignment(workshop_data)

    local next_job = workshop_data.job_queue and workshop_data.job_queue[1]
    if next_job then
      if M.start_job_now(workshop_data, next_job) then
        table.remove(workshop_data.job_queue, 1)
        return "working"
      end

      Status.set_blocked_status(workshop)
      return "working"
    end

    Status.set_idle_status(workshop)
    return "idle"
  end

  Status.set_finishing_status(workshop, assignment.item)
  return "working"
end

------------------------------------------------------------
-- WORKER TICKING
------------------------------------------------------------

function M.tick_workshop_worker(workshop_data, brain)
  local workshop = workshop_data and workshop_data.entity

  if not (workshop and workshop.valid) then
    return "invalid"
  end

  local requester = workshop_data.companions and workshop_data.companions.requester
  if not (requester and requester.valid) then
    Status.set_blocked_status(workshop)
    return "working"
  end

  local assignment = workshop_data.assignment
  if not assignment then
    return "idle"
  end

  local handler = STATE_HANDLERS[assignment.state]
  if handler then
    return handler(workshop_data, assignment, brain)
  end

  -- Unknown state: output any internal inventory, reset, go idle.
  if assignment.internal_inventory then
    M.output_internal_inventory(workshop_data, assignment)
  end
  M.reset_workshop_assignment(workshop_data)
  return "idle"
end

-- Re-export circuit controls for backward compatibility.
local WorkshopCircuit = require("scripts.workshop_circuit")
M.read_workshop_circuit_controls = WorkshopCircuit.read_workshop_circuit_controls

return M
