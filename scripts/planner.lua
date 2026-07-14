-- Logistic Nexus
-- Craft plan building: determines what to craft and what to request.

local Util = require("scripts.util")
local Recipes = require("scripts.recipes")
local Network = require("scripts.network")

local M = {}

------------------------------------------------------------
-- INTERNAL CRAFT PLAN
------------------------------------------------------------

local function build_plan_for_batches(
  workshop,
  network,
  target_name,
  quality,
  brain,
  options,
  batch_count
)
  local trace = options.trace
  local function log_trace(level, message)
    if not trace then
      return
    end
    table.insert(trace, string.rep("  ", level or 0) .. message)
  end

  log_trace(0, "Plan target: " .. target_name .. " (quality: " .. quality .. ")")

  local recipe, product_amount = Recipes.cached_recipe_for_item(
    brain,
    workshop,
    network.force,
    target_name
  )
  if not recipe then
    log_trace(0, "BLOCKED: no enabled recipe for " .. target_name)
    return nil, {
      reason = "uncraftable",
      item = target_name
    }
  end

  log_trace(0, "Recipe: " .. recipe.name
      .. " (category: " .. tostring(recipe.category)
      .. ", produces: " .. tostring(product_amount) .. ")")

  local root_ingredients = Recipes.aggregate_recipe_ingredients(recipe, batch_count, quality)
  local root_outputs = Recipes.recipe_outputs(recipe, quality)
  if not (root_ingredients and root_outputs) then
    log_trace(0, "BLOCKED: recipe " .. recipe.name .. " has unsupported ingredients/products")
    return nil, {
      reason = "unsupported",
      item = target_name
    }
  end

  local remaining_local = Util.copy_counts(options.local_counts)
  local remaining_internal = Util.copy_counts(options.internal_counts)
  local remaining_network = {}
  local requests = {}
  local network_used = {}
  local steps = {}

  local function available_for(name, item_quality)
    local key = Util.item_key(name, item_quality)
    if remaining_network[key] == nil then
      local budget = options.supply_budget
      local budget_count = budget and budget[key]

      if budget_count == nil then
        budget_count = Network.get_cached_supply_count(
          brain,
          network,
          name,
          item_quality
        )
        if budget then
          budget[key] = budget_count
        end
      end

      remaining_network[key] = math.max(0, budget_count or 0)
    end

    return remaining_network[key]
  end

  local function request_existing(name, amount, item_quality, level)
    local key = Util.item_key(name, item_quality)
    local internal_available = remaining_internal[key] or 0
    local internal_used = math.min(internal_available, amount)

    if internal_used > 0 then
      log_trace(level, "Use " .. internal_used .. " from internal buffer")
      remaining_internal[key] = internal_available - internal_used
      amount = amount - internal_used
    end

    if amount <= 0 then
      return 0
    end

    local local_available = remaining_local[key] or 0
    local local_used = math.min(local_available, amount)

    if local_used > 0 then
      log_trace(level, "Use " .. local_used .. " from requester/local stock")
      remaining_local[key] = local_available - local_used
      Util.add_count(requests, name, local_used, item_quality)
      amount = amount - local_used
    end

    if amount <= 0 then
      return 0
    end

    local available = available_for(name, item_quality)
    local requested = math.min(available, amount)

    if requested > 0 then
      log_trace(level, "Use " .. requested .. " from network (" .. available .. " available)")
      remaining_network[key] = available - requested
      Util.add_count(requests, name, requested, item_quality)
      Util.add_count(network_used, name, requested, item_quality)
    end

    local remaining = amount - requested
    if remaining > 0 then
      log_trace(level, "Must craft remaining: " .. remaining)
    end
    return remaining
  end

  local plan_item

  local function append_recipe_steps(name, amount, item_quality, trail, level)
    local child_recipe, child_product_amount = Recipes.cached_recipe_for_item(
      brain,
      workshop,
      network.force,
      name
    )
    if not child_recipe then
      log_trace(level, "BLOCKED: no enabled recipe for " .. name)
      return false, {
        reason = "missing-leaf",
        item = name
      }
    end

    local key = Util.item_key(name, item_quality)
    if trail[key] then
      log_trace(level, "BLOCKED: recipe cycle detected at " .. name)
      return false, {
        reason = "cycle",
        item = name
      }
    end

    local child_ingredients = Recipes.aggregate_recipe_ingredients(
      child_recipe,
      1,
      item_quality
    )
    local child_outputs = Recipes.recipe_outputs(child_recipe, item_quality)
    if not (child_ingredients and child_outputs and child_product_amount) then
      log_trace(level, "BLOCKED: recipe " .. child_recipe.name .. " has unsupported ingredients/products")
      return false, {
        reason = "unsupported",
        item = name
      }
    end

    trail[key] = true
    local craft_count = math.ceil(amount / child_product_amount)
    log_trace(level, "Craft using " .. child_recipe.name
        .. " (category: " .. tostring(child_recipe.category)
        .. ", produces: " .. tostring(child_product_amount) .. ")")
    log_trace(level, "Craft count: " .. craft_count)
    local produced = {}

    for _ = 1, craft_count do
      for _, ingredient in pairs(child_ingredients) do
        local ingredient_amount = Util.ingredient_count(ingredient)
        if not ingredient_amount then
          log_trace(level, "BLOCKED: ingredient " .. ingredient.name .. " has unsupported amount")
          trail[key] = nil
          return false, {reason = "unsupported-amount", item = ingredient.name}
        end

        log_trace(level + 1, "Need: " .. ingredient.name .. " x" .. ingredient_amount)
        local ok, blocked = plan_item(
          ingredient.name,
          ingredient_amount,
          ingredient.quality,
          trail,
          level + 1
        )

        if not ok then
          trail[key] = nil
          return false, blocked
        end
      end

      table.insert(steps, {
        item = name,
        quality = item_quality,
        recipe = child_recipe,
        recipe_name = child_recipe.name,
        ingredients = child_ingredients,
        outputs = child_outputs,
        product_amount = child_product_amount
      })

      for _, output in pairs(child_outputs) do
        Util.add_count(produced, output.name, output.amount, output.quality)
      end
    end

    for output_key, output_amount in pairs(produced) do
      remaining_internal[output_key] =
          (remaining_internal[output_key] or 0) + output_amount
    end

    remaining_internal[key] = math.max(
      0,
      (remaining_internal[key] or 0) - amount
    )

    trail[key] = nil
    return true, nil
  end

  function plan_item(name, amount, item_quality, trail, level)
    local remaining = request_existing(name, amount, item_quality, level)
    if remaining <= 0 then
      log_trace(level - 1, "Satisfied from existing stock")
      return true, nil
    end

    return append_recipe_steps(name, remaining, item_quality, trail, level)
  end

  for _, ingredient in pairs(root_ingredients) do
    local amount = Util.ingredient_count(ingredient)
    if not amount then
      log_trace(0, "BLOCKED: ingredient " .. ingredient.name .. " has unsupported amount")
      return nil, {reason = "unsupported-amount", item = ingredient.name}
    end

    log_trace(1, "Need: " .. ingredient.name .. " x" .. amount)
    local ok, blocked = plan_item(
      ingredient.name,
      amount,
      ingredient.quality,
      {},
      2
    )

    if not ok then
      return nil, blocked
    end
  end

  table.insert(steps, {
    item = target_name,
    quality = quality,
    recipe = recipe,
    recipe_name = recipe.name,
    ingredients = root_ingredients,
    outputs = root_outputs,
    product_amount = product_amount * batch_count
  })

  return {
    target_item = target_name,
    target_quality = quality,
    target_recipe = recipe.name,
    target_output_amount = (product_amount or 1) * batch_count,
    batch_count = batch_count,
    requests = Util.counts_to_ingredients(requests),
    network_used = network_used,
    steps = steps
  }, nil
end

function M.build_internal_craft_plan(
    workshop,
    network,
    target_name,
    quality,
    brain,
    options
  )
  quality = Util.quality_name(quality)
  options = options or {}

  local max_batches = options.max_batches or 1
  if max_batches < 1 then
    max_batches = 1
  end

  local one_batch_plan, one_batch_blocked = build_plan_for_batches(
    workshop,
    network,
    target_name,
    quality,
    brain,
    options,
    1
  )

  if not one_batch_plan then
    return nil, one_batch_blocked
  end

  if max_batches == 1 then
    return one_batch_plan, nil
  end

  local best_plan = one_batch_plan
  local low = 1
  local high = max_batches

  while low <= high do
    local mid = math.floor((low + high) / 2)
    local plan, _ = build_plan_for_batches(
      workshop,
      network,
      target_name,
      quality,
      brain,
      options,
      mid
    )

    if plan then
      best_plan = plan
      low = mid + 1
    else
      high = mid - 1
    end
  end

  return best_plan, nil
end

------------------------------------------------------------
-- PLAN DECORATION AND CANDIDATE BUILDING
------------------------------------------------------------

function M.decorate_plan(plan, shortage)
  plan.name = shortage.name
  plan.quality = shortage.quality or "normal"
  plan.plan_name = shortage.name
  plan.plan_quality = shortage.quality or "normal"
  plan.plan_priority = shortage.priority
  plan.product_amount = plan.target_output_amount or 1
  plan.batch_count = plan.batch_count or 1
  plan.construction_requested = shortage.construction_requested or 0
  return plan
end

function M.apply_supply_use(supply_budget, network_used)
  for name, count in pairs(network_used or {}) do
    local available = supply_budget[name]
    if available == nil then
      available = 0
    end
    supply_budget[name] = math.max(0, available - count)
  end
end

function M.build_candidate_plan(brain, workshop_data, network, candidate, supply_budget, max_batches)
  local requester = workshop_data.companions and workshop_data.companions.requester
  local plan, blocked = M.build_internal_craft_plan(
    workshop_data.entity,
    network,
    candidate.shortage.name,
    candidate.shortage.quality,
    brain,
    {
      local_counts = Network.requester_planning_counts(requester, true),
      supply_budget = supply_budget,
      max_batches = max_batches
    }
  )

  if plan then
    return M.decorate_plan(plan, candidate.shortage), nil
  end

  return nil, blocked
end

return M
