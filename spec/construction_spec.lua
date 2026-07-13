local helpers = require("spec.helpers")

helpers.install_globals()
local Construction = require("scripts.construction")

describe("construction", function()
  describe("ghost_key", function()
    it("uses unit_number when available", function()
      local entity = {unit_number = 42, name = "entity-ghost", position = {x = 1, y = 2}}
      assert.are.equal("u:42", Construction.ghost_key(entity))
    end)

    it("uses ghost_unit_number when no unit_number", function()
      local entity = {ghost_unit_number = 99, name = "entity-ghost", position = {x = 1, y = 2}}
      assert.are.equal("g:99", Construction.ghost_key(entity))
    end)

    it("falls back to name:ghost_name:position when no unit numbers", function()
      local entity = {
        name = "entity-ghost",
        ghost_name = "fast-inserter",
        position = {x = 5, y = 10}
      }
      assert.are.equal("entity-ghost:fast-inserter:5,10", Construction.ghost_key(entity))
    end)
  end)

  describe("add_requested_item", function()
    it("creates new entry when key does not exist", function()
      local requested = {}
      Construction.add_requested_item(requested, {
        name = "iron-plate",
        quality = "normal",
        requested = 5
      })
      local key = "iron-plate|normal"
      assert.is_not_nil(requested[key])
      assert.are.equal(5, requested[key].requested)
    end)

    it("accumulates into existing entry", function()
      local requested = {}
      Construction.add_requested_item(requested, {
        name = "iron-plate",
        quality = "normal",
        requested = 5,
        target = 10,
        contents = 2,
        incoming = 1
      })
      Construction.add_requested_item(requested, {
        name = "iron-plate",
        quality = "normal",
        requested = 3,
        target = 5,
        contents = 1,
        incoming = 2
      })
      local key = "iron-plate|normal"
      assert.are.equal(8, requested[key].requested)
      assert.are.equal(15, requested[key].target)
      assert.are.equal(3, requested[key].contents)
      assert.are.equal(3, requested[key].incoming)
    end)

    it("accumulates construction_requested", function()
      local requested = {}
      Construction.add_requested_item(requested, {
        name = "iron-plate",
        quality = "normal",
        requested = 5,
        construction_requested = 3
      })
      Construction.add_requested_item(requested, {
        name = "iron-plate",
        quality = "normal",
        requested = 2,
        construction_requested = 1
      })
      local key = "iron-plate|normal"
      assert.are.equal(4, requested[key].construction_requested)
    end)
  end)

  describe("construction_entity_items", function()
    it("returns empty for nil entity", function()
      assert.are.same({}, Construction.construction_entity_items(nil))
    end)

    it("returns empty for invalid entity", function()
      assert.are.same({}, Construction.construction_entity_items({valid = false}))
    end)

    it("returns items for item-request-proxy", function()
      local entity = {
        valid = true,
        type = "item-request-proxy",
        item_requests = {
          {name = "iron-plate", count = 5, quality = "normal"},
          {name = "copper-plate", count = 3, quality = "legendary"}
        }
      }
      local result = Construction.construction_entity_items(entity)
      assert.are.equal(2, #result)
      -- sorted? No, just iterated in order
    end)

    it("skips items with zero count", function()
      local entity = {
        valid = true,
        type = "item-request-proxy",
        item_requests = {
          {name = "iron-plate", count = 5, quality = "normal"},
          {name = "copper-plate", count = 0, quality = "normal"}
        }
      }
      local result = Construction.construction_entity_items(entity)
      assert.are.equal(1, #result)
      assert.are.equal("iron-plate", result[1].name)
    end)
  end)

  describe("add_ghost_request", function()
    local network = {network_id = 1, valid = true, force = {name = "player"}}

    it("adds item requests for entity ghosts", function()
      local ghost = {
        valid = true,
        type = "entity-ghost",
        quality = "normal",
        ghost_prototype = {
          items_to_place_this = {
            {name = "iron-plate", count = 2}
          }
        }
      }

      local counts = {}
      local added = Construction.add_ghost_request(counts, network, ghost)

      assert.is_true(added)
      local key = "1|iron-plate|normal"
      assert.is_not_nil(counts[key])
      assert.are.equal(2, counts[key].requested)
    end)

    it("adds item requests for tile ghosts", function()
      local ghost = {
        valid = true,
        type = "tile-ghost",
        quality = "normal",
        ghost_prototype = {
          items_to_place_this = {
            {name = "concrete", count = 10}
          }
        }
      }

      local counts = {}
      local added = Construction.add_ghost_request(counts, network, ghost)

      assert.is_true(added)
      local key = "1|concrete|normal"
      assert.is_not_nil(counts[key])
      assert.are.equal(10, counts[key].requested)
    end)

    it("returns false for tile ghosts without items_to_place_this", function()
      local ghost = {
        valid = true,
        type = "tile-ghost",
        quality = "normal",
        ghost_prototype = {
          items_to_place_this = nil
        }
      }

      local counts = {}
      local added = Construction.add_ghost_request(counts, network, ghost)

      assert.is_false(added)
    end)

    it("returns false for invalid ghost", function()
      local counts = {}
      local added = Construction.add_ghost_request(counts, network, {valid = false})
      assert.is_false(added)
    end)
  end)
end)
