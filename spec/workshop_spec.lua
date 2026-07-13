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

local Companions = {
  set_requester_requests = function() return true end,
  clear_requester_requests = function() end,
  freeze_requester_batch = function() end
}

package.loaded["scripts.status"] = Status
package.loaded["scripts.companions"] = Companions

local Workshop = require("scripts.workshop")

describe("workshop job queueing", function()
  local function make_entity(opts)
    opts = opts or {}
    return {
      valid = true,
      name = "logistic-nexus-workshop",
      unit_number = opts.unit_number or 1,
      position = opts.position or {x = 0, y = 0},
      products_finished = 0,
      crafting_progress = 0,
      get_recipe = function() return nil, nil end,
      set_recipe = function() return {} end,
      get_output_inventory = function()
        return {
          valid = true,
          is_empty = function() return true end,
          get_contents = function() return {} end
        }
      end,
      insert = function() return 0 end,
      surface = opts.surface or {spill_item_stack = function() end}
    }
  end

  local function make_requester()
    return {
      valid = true,
      name = "logistic-nexus-requester",
      get_inventory = function()
        return {
          valid = true,
          is_empty = function() return true end,
          get_contents = function() return {} end,
          remove = function() return 0 end
        }
      end
    }
  end

  local function make_provider()
    return {
      valid = true,
      name = "logistic-nexus-provider",
      insert = function() return 0 end
    }
  end

  local function make_workshop_data(opts)
    opts = opts or {}
    local entity = opts.entity or make_entity()
    return {
      entity = entity,
      companions = opts.companions or {
        requester = make_requester(),
        provider = make_provider()
      },
      assignment = opts.assignment,
      job_queue = opts.job_queue
    }
  end

  local function make_job(name, output)
    return {
      target_item = name,
      target_quality = "normal",
      target_recipe = name,
      requests = {},
      steps = {},
      product_amount = output or 1
    }
  end

  describe("can_accept_job", function()
    it("returns true for an idle workshop with an empty queue", function()
      local workshop_data = make_workshop_data()
      assert.is_true(Workshop.can_accept_job(workshop_data))
    end)

    it("returns true when an assignment is active and queue has space", function()
      local workshop_data = make_workshop_data({
        assignment = {state = "waiting_inputs", item = "iron-plate"}
      })
      assert.is_true(Workshop.can_accept_job(workshop_data))
    end)

    it("returns false when the queue is full", function()
      local C = require("scripts.constants")
      local queue = {}
      for _ = 1, C.WORKSHOP_QUEUE_SIZE do
        table.insert(queue, make_job("iron-plate"))
      end
      local workshop_data = make_workshop_data({job_queue = queue})
      assert.is_false(Workshop.can_accept_job(workshop_data))
    end)

    it("returns true when the queue has space", function()
      local workshop_data = make_workshop_data({
        job_queue = {make_job("iron-plate")}
      })
      assert.is_true(Workshop.can_accept_job(workshop_data))
    end)
  end)

  describe("queue_job", function()
    it("starts immediately when the workshop is idle", function()
      local workshop_data = make_workshop_data()
      local job = make_job("iron-plate", 2)

      local ok = Workshop.queue_job(workshop_data, job)

      assert.is_true(ok)
      assert.is_not_nil(workshop_data.assignment)
      assert.are.equal("iron-plate", workshop_data.current_item)
      assert.are.equal(2, workshop_data.current_product_amount)
      assert.is_true(workshop_data.job_queue == nil or #workshop_data.job_queue == 0)
    end)

    it("enqueues a job when another job is active", function()
      local workshop_data = make_workshop_data({
        assignment = {state = "crafting_step", item = "iron-plate"}
      })
      local job = make_job("copper-plate", 3)

      local ok = Workshop.queue_job(workshop_data, job)

      assert.is_true(ok)
      assert.are.equal("iron-plate", workshop_data.assignment.item)
      assert.are.equal(1, #workshop_data.job_queue)
      assert.are.equal("copper-plate", workshop_data.job_queue[1].target_item)
    end)

    it("refuses to enqueue when the queue is full", function()
      local C = require("scripts.constants")
      local queue = {}
      for _ = 1, C.WORKSHOP_QUEUE_SIZE do
        table.insert(queue, make_job("iron-plate"))
      end
      local workshop_data = make_workshop_data({
        assignment = {state = "crafting_step", item = "copper-plate"},
        job_queue = queue
      })

      local ok = Workshop.queue_job(workshop_data, make_job("steel-plate"))

      assert.is_false(ok)
      assert.are.equal(C.WORKSHOP_QUEUE_SIZE, #workshop_data.job_queue)
    end)
  end)

  describe("tick_workshop_worker queue drain", function()
    it("starts the next queued job when draining completes", function()
      local entity = make_entity()
      local workshop_data = make_workshop_data({
        entity = entity,
        assignment = {
          state = "draining",
          item = "iron-plate",
          quality = "normal",
          internal_inventory = {}
        },
        job_queue = {make_job("copper-plate", 5)}
      })

      local state = Workshop.tick_workshop_worker(workshop_data, {})

      assert.are.equal("busy", state)
      assert.is_not_nil(workshop_data.assignment)
      assert.are.equal("copper-plate", workshop_data.current_item)
      assert.are.equal(5, workshop_data.current_product_amount)
      assert.are.equal(0, #workshop_data.job_queue)
    end)

    it("becomes idle when draining completes with an empty queue", function()
      local entity = make_entity()
      local workshop_data = make_workshop_data({
        entity = entity,
        assignment = {
          state = "draining",
          item = "iron-plate",
          quality = "normal",
          internal_inventory = {}
        },
        job_queue = {}
      })

      local state = Workshop.tick_workshop_worker(workshop_data, {})

      assert.are.equal("idle", state)
      assert.is_nil(workshop_data.assignment)
    end)
  end)
end)

describe("brain active assignment accounting with queues", function()
  local Brain = require("scripts.brain")

  it("counts queued jobs in active outputs", function()
    storage.workshops = {
      [1] = {
        assignment = {
          state = "crafting_step",
          item = "iron-plate",
          quality = "normal",
          expected_output = 2
        },
        job_queue = {
          {target_item = "copper-plate", target_quality = "normal", product_amount = 3},
          {target_item = "copper-plate", target_quality = "normal", product_amount = 4}
        }
      }
    }

    local brain = {workshops = {1}}
    local machines, outputs = Brain.collect_active_assignments(brain)

    assert.are.equal(1, machines["iron-plate|normal"])
    assert.are.equal(2, outputs["iron-plate|normal"])
    assert.are.equal(2, machines["copper-plate|normal"])
    assert.are.equal(7, outputs["copper-plate|normal"])
  end)
end)
