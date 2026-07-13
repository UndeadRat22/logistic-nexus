local helpers = require("spec.helpers")

helpers.install_globals()

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
