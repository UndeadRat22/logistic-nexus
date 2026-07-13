local helpers = require("spec.helpers")

helpers.install_globals()

local Gui = require("scripts.gui")

describe("gui prepare_status_data", function()
  it("returns default data when brain is missing", function()
    local data = Gui.prepare_status_data(nil)

    assert.are.equal(0, data.tick)
    assert.are.equal(0, data.total_workshops)
    assert.are.equal(0, data.idle_workshops)
    assert.are.equal(0, data.assigned_workshops)
    assert.are.equal(0, data.request_count)
    assert.are.equal(0, data.shortage_count)
    assert.are.same({}, data.targets)
    assert.are.same({}, data.workers)
  end)

  it("returns default data when last_analysis is missing", function()
    local data = Gui.prepare_status_data({})
    assert.are.equal(0, data.tick)
    assert.are.same({}, data.targets)
  end)

  it("summarizes analysis fields", function()
    local brain = {
      last_analysis = {
        tick = 1234,
        total_workshops = 5,
        idle_workshops = 2,
        assigned_workshops = 3,
        request_count = 10,
        shortage_count = 4,
        targets = {
          {
            name = "iron-plate",
            quality = "normal",
            missing = 100,
            available = 20,
            active = 2,
            remaining_units = 80,
            blocked_reason = nil
          }
        },
        workers = {
          {
            unit_number = 42,
            state = "crafting_step",
            target = "iron-plate",
            quality = "normal",
            present = 5,
            incoming = 3,
            missing = "copper-plate"
          }
        }
      }
    }

    local data = Gui.prepare_status_data(brain)

    assert.are.equal(1234, data.tick)
    assert.are.equal(5, data.total_workshops)
    assert.are.equal(2, data.idle_workshops)
    assert.are.equal(3, data.assigned_workshops)
    assert.are.equal(10, data.request_count)
    assert.are.equal(4, data.shortage_count)
    assert.are.equal(1, #data.targets)
    assert.are.equal("iron-plate", data.targets[1].name)
    assert.are.equal(100, data.targets[1].missing)
    assert.are.equal(1, #data.workers)
    assert.are.equal(42, data.workers[1].unit_number)
    assert.are.equal("copper-plate", data.workers[1].missing)
  end)

  it("marks blocked targets", function()
    local brain = {
      last_analysis = {
        targets = {
          {
            name = "advanced-circuit",
            quality = "normal",
            missing = 10,
            available = 0,
            active = 0,
            remaining_units = 10,
            blocked_reason = "uncraftable"
          }
        }
      }
    }

    local data = Gui.prepare_status_data(brain)

    assert.is_true(data.targets[1].is_blocked)
    assert.are.equal("uncraftable", data.targets[1].blocked_reason)
  end)

  it("marks unblocked targets", function()
    local brain = {
      last_analysis = {
        targets = {
          {
            name = "iron-plate",
            quality = "normal",
            missing = 10,
            available = 5,
            active = 1,
            remaining_units = 5,
            blocked_reason = nil
          }
        }
      }
    }

    local data = Gui.prepare_status_data(brain)

    assert.is_false(data.targets[1].is_blocked)
  end)
end)
