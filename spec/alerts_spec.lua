local helpers = require("spec.helpers")

helpers.install_globals()
local C = require("scripts.constants")
local Alerts = require("scripts.alerts")

describe("alerts", function()
  describe("should_alert", function()
    it("returns true on first alert", function()
      local brain = {}
      assert.is_true(Alerts.should_alert(brain, "iron-plate", 100))
    end)

    it("returns false within cooldown", function()
      local brain = {}
      Alerts.record_alert(brain, "iron-plate", 100)
      assert.is_false(Alerts.should_alert(brain, "iron-plate", 100 + C.ALERT_COOLDOWN_TICKS - 1))
    end)

    it("returns true after cooldown", function()
      local brain = {}
      Alerts.record_alert(brain, "iron-plate", 100)
      assert.is_true(Alerts.should_alert(brain, "iron-plate", 100 + C.ALERT_COOLDOWN_TICKS))
    end)

    it("tracks different items independently", function()
      local brain = {}
      Alerts.record_alert(brain, "iron-plate", 100)
      assert.is_true(Alerts.should_alert(brain, "copper-plate", 100))
      assert.is_false(Alerts.should_alert(brain, "iron-plate", 100))
    end)
  end)

  describe("record_alert", function()
    it("stores the tick for an item", function()
      local brain = {}
      Alerts.record_alert(brain, "iron-plate", 250)
      assert.are.equal(250, brain.last_alerts["iron-plate"])
    end)
  end)

  describe("alert_blocked_item", function()
    it("creates flying text when alert is allowed", function()
      local created = false
      local brain = {}
      local workshop_data = {
        entity = {
          valid = true,
          position = {x = 10, y = 20},
          surface = {
            create_entity = function(params)
              created = true
              assert.are.equal("flying-text", params.name)
              assert.are.equal(10, params.position.x)
              assert.are.equal(20, params.position.y)
              assert.is_not_nil(params.text)
              return {valid = true}
            end
          }
        }
      }

      Alerts.alert_blocked_item(brain, workshop_data, "iron-plate", "uncraftable", 100)

      assert.is_true(created)
      assert.are.equal(100, brain.last_alerts["iron-plate"])
    end)

    it("does not create flying text during cooldown", function()
      local created = false
      local brain = {}
      Alerts.record_alert(brain, "iron-plate", 100)
      local workshop_data = {
        entity = {
          valid = true,
          position = {x = 0, y = 0},
          surface = {
            create_entity = function()
              created = true
              return {valid = true}
            end
          }
        }
      }

      Alerts.alert_blocked_item(brain, workshop_data, "iron-plate", "uncraftable", 100 + 10)

      assert.is_false(created)
    end)
  end)
end)
