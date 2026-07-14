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
    local categories = opts.categories or (opts.category and {opts.category}) or {"crafting"}
    return {
      name = opts.name,
      valid = true,
      enabled = opts.enabled ~= false,
      hidden = opts.hidden or false,
      categories = categories,
      energy = opts.energy or 1,
      products = opts.products or {{type = "item", name = opts.name, amount = 1}},
      ingredients = opts.ingredients or {},
      has_category = function(cat)
        for _, c in ipairs(categories) do
          if c == cat then
            return true
          end
        end
        return false
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
      local recipes = helpers.make_iron_gear_recipes(make_recipe)
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

  describe("build_internal_craft_plan batching", function()
    it("scales requests and output with max_batches when supply is available", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 2}}
        })
      }
      network_available = {["iron-ore"] = 100}

      local plan = Planner.build_internal_craft_plan(
        make_workshop(),
        make_network(recipes),
        "iron-plate",
        "normal",
        {recipe_choices = {}, raw_supply_counts = {}},
        {max_batches = 5}
      )

      assert.is_not_nil(plan)
      assert.are.equal(5, plan.target_output_amount)
      assert.are.equal(1, #plan.requests)
      assert.are.equal("iron-ore", plan.requests[1].name)
      assert.are.equal(10, plan.requests[1].amount)
    end)

    it("falls back to fewer batches when supply is limited", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 2}}
        })
      }
      network_available = {["iron-ore"] = 6}

      local plan = Planner.build_internal_craft_plan(
        make_workshop(),
        make_network(recipes),
        "iron-plate",
        "normal",
        {recipe_choices = {}, raw_supply_counts = {}},
        {max_batches = 5}
      )

      assert.is_not_nil(plan)
      assert.are.equal(3, plan.target_output_amount)
      assert.are.equal(6, plan.requests[1].amount)
    end)

    it("returns nil when even one batch is infeasible", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 2}}
        })
      }
      network_available = {}

      local plan, blocked = Planner.build_internal_craft_plan(
        make_workshop(),
        make_network(recipes),
        "iron-plate",
        "normal",
        {recipe_choices = {}, raw_supply_counts = {}},
        {max_batches = 5}
      )

      assert.is_nil(plan)
      assert.are.equal("missing-leaf", blocked.reason)
      assert.are.equal("iron-ore", blocked.item)
    end)

    it("matches single-batch output when max_batches is 1", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 2}}
        })
      }
      network_available = {["iron-ore"] = 100}

      local plan = Planner.build_internal_craft_plan(
        make_workshop(),
        make_network(recipes),
        "iron-plate",
        "normal",
        {recipe_choices = {}, raw_supply_counts = {}},
        {max_batches = 1}
      )

      assert.is_not_nil(plan)
      assert.are.equal(1, plan.target_output_amount)
      assert.are.equal(2, plan.requests[1].amount)
    end)
  end)
end)
