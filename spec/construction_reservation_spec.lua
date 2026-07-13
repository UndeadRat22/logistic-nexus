local helpers = require("spec.helpers")

helpers.install_globals()
local Construction = require("scripts.construction")
local Storage = require("scripts.storage")
local Util = require("scripts.util")

describe("construction reservations", function()
  before_each(function()
    Storage.init_storage()
    storage.construction_reservations = {}
    game.tick = 0
  end)

  local function make_network(id)
    return {
      network_id = id,
      valid = true,
      force = {name = "player"}
    }
  end

  local function make_workshop_data(network, target, item, quality)
    return {
      current_is_construction = true,
      current_item = item or "iron-plate",
      current_quality = quality or "normal",
      current_construction_target = target or 10,
      current_construction_reserved = 0,
      companions = {
        requester = {
          valid = true,
          get_logistic_point = function()
            return {
              valid = true,
              logistic_network = network
            }
          end
        }
      },
      entity = {
        valid = true,
        position = {x = 0, y = 0},
        force = network.force,
        surface = {
          find_logistic_network_by_position = function()
            return network
          end
        }
      }
    }
  end

  describe("reserve_construction_output", function()
    it("reserves up to count when target not yet met", function()
      local network = make_network(1)
      local workshop_data = make_workshop_data(network, 10)

      Construction.reserve_construction_output(workshop_data, 5)

      local key = Util.construction_reservation_key(network, "iron-plate", "normal")
      assert.are.equal(5, storage.construction_reservations[key].count)
      assert.are.equal(5, workshop_data.current_construction_reserved)
    end)

    it("does not exceed the construction target", function()
      local network = make_network(1)
      local workshop_data = make_workshop_data(network, 5)

      Construction.reserve_construction_output(workshop_data, 10)

      local key = Util.construction_reservation_key(network, "iron-plate", "normal")
      assert.are.equal(5, storage.construction_reservations[key].count)
    end)

    it("clamps against shared reservation total across workshops", function()
      local network = make_network(1)
      local workshop_a = make_workshop_data(network, 10)
      local workshop_b = make_workshop_data(network, 10)

      Construction.reserve_construction_output(workshop_a, 6)
      Construction.reserve_construction_output(workshop_b, 6)

      local key = Util.construction_reservation_key(network, "iron-plate", "normal")
      assert.are.equal(10, storage.construction_reservations[key].count)
      assert.are.equal(6, workshop_a.current_construction_reserved)
      assert.are.equal(4, workshop_b.current_construction_reserved)
    end)

    it("ignores non-construction workshops", function()
      local network = make_network(1)
      local workshop_data = make_workshop_data(network, 10)
      workshop_data.current_is_construction = false

      Construction.reserve_construction_output(workshop_data, 5)

      local key = Util.construction_reservation_key(network, "iron-plate", "normal")
      assert.is_nil(storage.construction_reservations[key])
    end)
  end)

  describe("prune_construction_reservations", function()
    it("preserves reservations for items still requested", function()
      local network = make_network(1)
      local workshop_data = make_workshop_data(network, 10)

      Construction.reserve_construction_output(workshop_data, 5)

      local key = Util.construction_reservation_key(network, "iron-plate", "normal")
      assert.are.equal(5, storage.construction_reservations[key].count)

      -- live_counts maps reservation keys to the live ghost request count
      local live_counts = {}
      live_counts[key] = 10

      Construction.prune_construction_reservations(network, live_counts)

      assert.is_not_nil(storage.construction_reservations[key])
      assert.are.equal(5, storage.construction_reservations[key].count)
    end)

    it("removes reservations for items no longer requested", function()
      local network = make_network(1)
      local workshop_data = make_workshop_data(network, 10)

      Construction.reserve_construction_output(workshop_data, 5)

      local key = Util.construction_reservation_key(network, "iron-plate", "normal")

      -- Empty live_counts: the item is no longer requested
      Construction.prune_construction_reservations(network, {})

      assert.is_nil(storage.construction_reservations[key])
    end)

    it("clamps reservation count down to live request count", function()
      local network = make_network(1)
      local workshop_data = make_workshop_data(network, 10)

      Construction.reserve_construction_output(workshop_data, 8)

      local key = Util.construction_reservation_key(network, "iron-plate", "normal")

      local live_counts = {}
      live_counts[key] = 3

      Construction.prune_construction_reservations(network, live_counts)

      assert.is_not_nil(storage.construction_reservations[key])
      assert.are.equal(3, storage.construction_reservations[key].count)
    end)
  end)
end)
