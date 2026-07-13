local helpers = require("spec.helpers")

helpers.install_globals()
local Planner = require("scripts.planner")
local Network = require("scripts.network")

describe("planner", function()
  local original_get_cached_supply_count
  local network_available = {}

  local function make_workshop()
    return {
      prototype = {
        crafting_categories = {crafting = true}
      }
    }
  end

  local function make_recipe(opts)
    return {
      name = opts.name,
      valid = true,
      enabled = opts.enabled ~= false,
      hidden = opts.hidden or false,
      category = opts.category or "crafting",
      energy = opts.energy or 1,
      products = opts.products or {{type = "item", name = opts.name, amount = 1}},
      ingredients = opts.ingredients or {},
      has_category = function(cat)
        return (opts.category or "crafting") == cat
      end
    }
  end

  local function make_network(recipes)
    return {
      force = {
        recipes = recipes or {}
      }
    }
  end

  before_each(function()
    original_get_cached_supply_count = Network.get_cached_supply_count
    Network.get_cached_supply_count = function(_, _, name, _)
      return network_available[name] or 0
    end
  end)

  after_each(function()
    Network.get_cached_supply_count = original_get_cached_supply_count
    network_available = {}
  end)

  describe("build_internal_craft_plan trace", function()
    it("logs a satisfied-by-network plan", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 2}}
        })
      }
      network_available = {["iron-ore"] = 5}
      local trace = {}

      local plan, blocked = Planner.build_internal_craft_plan(
        make_workshop(),
        make_network(recipes),
        "iron-plate",
        "normal",
        {recipe_choices = {}, raw_supply_counts = {}},
        {trace = trace}
      )

      assert.is_not_nil(plan)
      assert.is_nil(blocked)
      assert.is_true(#trace > 0)
      local trace_str = table.concat(trace, "\n")
      assert.is_true(trace_str:find("Plan target: iron%-plate") ~= nil)
      assert.is_true(trace_str:find("Recipe: iron%-plate") ~= nil)
      assert.is_true(trace_str:find("Need: iron%-ore x2") ~= nil)
      assert.is_true(trace_str:find("Use 2 from network") ~= nil)
    end)

    it("logs a blocked plan when an intermediate has no recipe", function()
      local recipes = {
        ["advanced-circuit"] = make_recipe({
          name = "advanced-circuit",
          ingredients = {
            {type = "item", name = "electronic-circuit", amount = 2},
            {type = "item", name = "plastic-bar", amount = 2}
          }
        }),
        ["electronic-circuit"] = make_recipe({
          name = "electronic-circuit",
          ingredients = {{type = "item", name = "iron-plate", amount = 1}}
        }),
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 1}}
        })
      }
      network_available = {["iron-ore"] = 10}
      local trace = {}

      local plan, blocked = Planner.build_internal_craft_plan(
        make_workshop(),
        make_network(recipes),
        "advanced-circuit",
        "normal",
        {recipe_choices = {}, raw_supply_counts = {}},
        {trace = trace}
      )

      assert.is_nil(plan)
      assert.are.equal("missing-leaf", blocked.reason)
      assert.are.equal("plastic-bar", blocked.item)
      local trace_str = table.concat(trace, "\n")
      assert.is_true(trace_str:find("BLOCKED: no enabled recipe for plastic%-bar") ~= nil)
    end)

    it("logs internal crafting when network supply is insufficient", function()
      local recipes = {
        ["iron-gear-wheel"] = make_recipe({
          name = "iron-gear-wheel",
          ingredients = {{type = "item", name = "iron-plate", amount = 2}}
        }),
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 1}}
        })
      }
      network_available = {["iron-plate"] = 1, ["iron-ore"] = 5}
      local trace = {}

      local plan, blocked = Planner.build_internal_craft_plan(
        make_workshop(),
        make_network(recipes),
        "iron-gear-wheel",
        "normal",
        {recipe_choices = {}, raw_supply_counts = {}},
        {trace = trace}
      )

      assert.is_not_nil(plan)
      assert.is_nil(blocked)
      local trace_str = table.concat(trace, "\n")
      assert.is_true(trace_str:find("Use 1 from network") ~= nil)
      assert.is_true(trace_str:find("Must craft remaining: 1") ~= nil)
      assert.is_true(trace_str:find("Craft using iron%-plate") ~= nil)
    end)
  end)
end)
