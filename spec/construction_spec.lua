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

  describe("collect_shortages", function()
    local function make_requester_point(filters, owner_contents)
      local call_count = 0
      local owner = {
        valid = true,
        type = "logistic-container",
        get_inventory = function()
          call_count = call_count + 1
          return {
            valid = true,
            get_item_count = function(item)
              if type(item) == "table" then
                local key = item.name .. "|" .. (item.quality or "normal")
                return owner_contents[key] or 0
              end
              return owner_contents[item .. "|normal"] or 0
            end,
            get_contents = function()
              local result = {}
              for key, count in pairs(owner_contents) do
                local name, quality = key:match("^(.*)|([^|]+)$")
                table.insert(result, {name = name, count = count, quality = quality})
              end
              return result
            end,
            is_empty = function() return false end
          }
        end
      }
      return {
        valid = true,
        enabled = true,
        owner = owner,
        filters = filters,
        targeted_items_deliver = {},
        _get_inventory_call_count = function() return call_count end
      }
    end

    local function make_network(points)
      return {
        valid = true,
        network_id = 1,
        force = {name = "player"},
        requester_points = points or {},
        cells = {}
      }
    end

    it("collects shortages from requester points", function()
      local point = make_requester_point(
        {{name = "iron-plate", quality = "normal", count = 10}},
        {["iron-plate|normal"] = 3}
      )
      local network = make_network({point})
      game.tick = 0

      local shortages, count = Construction.collect_shortages(network, nil)

      assert.are.equal(1, #shortages)
      assert.are.equal("iron-plate", shortages[1].name)
      assert.are.equal(7, shortages[1].missing)
      assert.are.equal(3, shortages[1].contents)
      assert.are.equal(10, shortages[1].target)
    end)

    it("skips satisfied requests", function()
      local point = make_requester_point(
        {{name = "iron-plate", quality = "normal", count = 5}},
        {["iron-plate|normal"] = 10}
      )
      local network = make_network({point})
      game.tick = 0

      local shortages = Construction.collect_shortages(network, nil)
      assert.are.equal(0, #shortages)
    end)

    it("aggregates duplicate filters within a point", function()
      local point = make_requester_point(
        {
          {name = "iron-plate", quality = "normal", count = 5},
          {name = "iron-plate", quality = "normal", count = 3}
        },
        {["iron-plate|normal"] = 2}
      )
      local network = make_network({point})
      game.tick = 0

      local shortages = Construction.collect_shortages(network, nil)
      assert.are.equal(1, #shortages)
      assert.are.equal(8, shortages[1].target)
      assert.are.equal(6, shortages[1].missing)
    end)

    it("handles multiple points requesting different items", function()
      local point_a = make_requester_point(
        {{name = "iron-plate", quality = "normal", count = 10}},
        {["iron-plate|normal"] = 0}
      )
      local point_b = make_requester_point(
        {{name = "copper-plate", quality = "normal", count = 5}},
        {["copper-plate|normal"] = 0}
      )
      local network = make_network({point_a, point_b})
      game.tick = 0

      local shortages = Construction.collect_shortages(network, nil)
      assert.are.equal(2, #shortages)
    end)

    it("calls get_inventory once per requester point, not once per filter", function()
      local point = make_requester_point(
        {
          {name = "iron-plate", quality = "normal", count = 10},
          {name = "copper-plate", quality = "normal", count = 5},
          {name = "steel-plate", quality = "normal", count = 2}
        },
        {
          ["iron-plate|normal"] = 0,
          ["copper-plate|normal"] = 0,
          ["steel-plate|normal"] = 0
        }
      )
      local network = make_network({point})
      game.tick = 0

      Construction.collect_shortages(network, nil)

      -- With the get_contents() optimization, get_inventory should be called
      -- exactly once per requester point, not once per filter.
      assert.are.equal(1, point._get_inventory_call_count())
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
