local helpers = require("spec.helpers")

helpers.install_globals()

-- Stub Registration before loading Events.
package.loaded["scripts.registration"] = {
  sync_barrelled_recipes = function() end,
  rebuild_workshops = function() end
}

local Events = require("scripts.events")
local Brain = require("scripts.brain")
local C = require("scripts.constants")

describe("events register_events", function()
  it("registers assess_all_workshops on nth_tick with ASSESS_INTERVAL", function()
    local captured_interval = nil
    local captured_handler = nil

    _G.script.on_nth_tick = function(interval, handler)
      captured_interval = interval
      captured_handler = handler
    end

    _G.script.on_init = function() end
    _G.script.on_configuration_changed = function() end
    _G.script.on_event = function() end
    _G.commands.add_command = function() end

    Events.register_events()

    assert.are.equal(C.ASSESS_INTERVAL, captured_interval)
    assert.are.equal(Brain.assess_all_workshops, captured_handler)
  end)
end)

describe("on_configuration_changed", function()
  it("clears stale upgrade_marked entries", function()
    storage.upgrade_marked = {
      [1] = {valid = true, unit_number = 1, surface = {index = 1}, position = {x = 0, y = 0}},
      [2] = {valid = false, unit_number = 2, surface = {index = 1}, position = {x = 0, y = 0}}
    }

    Events.on_configuration_changed()

    assert.are.same({}, storage.upgrade_marked)
  end)
end)
