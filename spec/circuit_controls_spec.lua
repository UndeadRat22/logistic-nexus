local helpers = require("spec.helpers")

helpers.install_globals()

-- Stub dependencies before loading workshop module.
local Status = {
  set_idle_status = function() end,
  set_blocked_status = function() end,
  set_no_network_status = function() end,
  set_no_shortage_status = function() end,
  set_working_status = function() end,
  set_finishing_status = function() end,
  set_goal_sprite = function() end,
  destroy_goal_sprite = function() end
}
package.loaded["scripts.status"] = Status

local Network = {
  get_requester_point = function() return nil end,
  get_item_count_from_inventory = function() return 0 end,
  targeted_delivery_count = function() return 0 end
}
package.loaded["scripts.network"] = Network

local Companions = {
  set_requester_requests = function() return true end,
  clear_requester_requests = function() end,
  freeze_requester_batch = function() end
}
package.loaded["scripts.companions"] = Companions

local Construction = {
  reserve_construction_output = function() end
}
package.loaded["scripts.construction"] = Construction

local Planner = {
  build_candidate_plan = function() return nil, {reason = "test"} end,
  apply_supply_use = function() end
}
package.loaded["scripts.planner"] = Planner

local Storage = {
  preflight_replans_remaining = 0
}
package.loaded["scripts.storage"] = Storage

local Workshop = require("scripts.workshop")
local C = require("scripts.constants")

describe("read_workshop_circuit_controls", function()
  local function make_entity(signals)
    return {
      valid = true,
      name = "logistic-nexus-workshop",
      unit_number = 1,
      get_signals = function()
        return signals or {}
      end
    }
  end

  it("returns excluded_items table with item signals excluded", function()
    local entity = make_entity({
      {
        signal = {type = "item", name = "solar-panel"},
        count = 1
      },
      {
        signal = {type = "item", name = "iron-plate"},
        count = 5
      }
    })

    local controls = Workshop.read_workshop_circuit_controls(entity)

    assert.is_true(controls.excluded_items["solar-panel"])
    assert.is_true(controls.excluded_items["iron-plate"])
    assert.is_nil(controls.excluded_items["copper-plate"])
  end)

  it("returns default product_limit when no signal-P is present", function()
    local entity = make_entity({})

    local controls = Workshop.read_workshop_circuit_controls(entity)

    assert.are.equal(C.DEFAULT_PRODUCT_LIMIT, controls.product_limit)
  end)

  it("sets product_limit from signal-P", function()
    local entity = make_entity({
      {
        signal = {type = "virtual", name = "signal-P"},
        count = 5
      }
    })

    local controls = Workshop.read_workshop_circuit_controls(entity)

    assert.are.equal(5, controls.product_limit)
  end)

  it("ignores zero and negative signals", function()
    local entity = make_entity({
      {
        signal = {type = "item", name = "solar-panel"},
        count = 0
      },
      {
        signal = {type = "item", name = "iron-plate"},
        count = -3
      }
    })

    local controls = Workshop.read_workshop_circuit_controls(entity)

    assert.is_nil(controls.excluded_items["solar-panel"])
    assert.is_nil(controls.excluded_items["iron-plate"])
  end)

  it("returns safe defaults when entity is invalid", function()
    local entity = {valid = false}

    local controls = Workshop.read_workshop_circuit_controls(entity)

    assert.are.same({}, controls.excluded_items)
    assert.are.equal(C.DEFAULT_PRODUCT_LIMIT, controls.product_limit)
  end)
end)

describe("choose_independent_job respects circuit exclusion", function()
  -- This test exercises the real integration: an item excluded by circuit
  -- signal must be skipped by choose_independent_job. Before the fix, the
  -- function read controls.excludedItems (camelCase, always nil) instead of
  -- controls.excluded_items (snake_case), so excluded items were never skipped.

  local Brain = require("scripts.brain")
  local Planner = require("scripts.planner")

  local function make_workshop_data(excluded_item)
    local entity = {
      valid = true,
      name = "logistic-nexus-workshop",
      unit_number = 1,
      get_signals = function()
        if not excluded_item then return {} end
        return {
          {
            signal = {type = "item", name = excluded_item},
            count = 1
          }
        }
      end
    }
    return {
      entity = entity,
      companions = {requester = {valid = true}},
      assignment = nil,
      job_queue = {}
    }
  end

  local function make_candidate(name)
    return {
      key = name .. "|normal",
      shortage = {name = name, quality = "normal"},
      product_amount = 1,
      remaining_units = 5,
      machine_count = 0,
      blocked_reason = nil
    }
  end

  it("skips candidates whose item is excluded by circuit signal", function()
    local workshop_data = make_workshop_data("solar-panel")
    local brain = {recipe_choices = {}, raw_supply_counts = {}}
    local network = {valid = true, force = {name = "player"}}

    local candidates = {
      make_candidate("solar-panel"),
      make_candidate("iron-plate")
    }

    -- Planner returns a plan for any candidate it's asked about.
    -- If solar-panel is correctly excluded, the planner will only be
    -- called for iron-plate, and we'll get a non-nil result.
    local call_count = 0
    Planner.build_candidate_plan = function(_, _, _, candidate, _)
      call_count = call_count + 1
      return {
        target_item = candidate.shortage.name,
        target_quality = "normal",
        target_recipe = candidate.shortage.name,
        product_amount = 1,
        requests = {},
        steps = {},
        network_used = {},
        plan_name = candidate.shortage.name,
        plan_quality = "normal",
        plan_priority = 1,
        construction_requested = 0
      }, nil
    end

    local plan, candidate = Brain.choose_independent_job(
      brain, workshop_data, network, candidates, {}
    )

    -- Should have skipped solar-panel and planned iron-plate instead
    assert.is_not_nil(plan)
    assert.are.equal("iron-plate", candidate.shortage.name)
    assert.are.equal(1, call_count) -- only called once (for iron-plate)
  end)

  it("returns nil when all candidates are excluded", function()
    local workshop_data = make_workshop_data("solar-panel")
    local brain = {recipe_choices = {}, raw_supply_counts = {}}
    local network = {valid = true, force = {name = "player"}}

    local candidates = {
      make_candidate("solar-panel"),
      make_candidate("solar-panel")
    }

    Planner.build_candidate_plan = function()
      return {requests = {}, steps = {}, network_used = {}}, nil
    end

    local plan = Brain.choose_independent_job(
      brain, workshop_data, network, candidates, {}
    )

    assert.is_nil(plan)
  end)
end)
