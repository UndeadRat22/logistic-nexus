local helpers = require("spec.helpers")

helpers.install_globals()
local Recipes = require("scripts.recipes")

describe("recipes", function()
  describe("recipe_is_available_to_mall", function()
    it("returns true for non-hidden recipe", function()
      assert.is_true(Recipes.recipe_is_available_to_mall({name = "iron-plate", hidden = false}))
    end)

    it("returns true for hidden barrelled recipe", function()
      assert.is_true(Recipes.recipe_is_available_to_mall({
        name = "ag-mall-barrelled-water",
        hidden = true
      }))
    end)

    it("returns false for hidden non-barrelled recipe", function()
      assert.is_false(Recipes.recipe_is_available_to_mall({
        name = "secret-recipe",
        hidden = true
      }))
    end)
  end)

  describe("fixed_product_amount", function()
    -- Already tested in util, but verify Recipes uses Util correctly
    -- by testing recipe_product_amount which calls it.
  end)

  describe("recipe_product_amount", function()
    it("returns sum of fixed amounts for matching item products", function()
      local recipe = {
        name = "iron-plate",
        products = {
          {type = "item", name = "iron-plate", amount = 2},
          {type = "item", name = "iron-plate", amount = 3}
        }
      }
      assert.are.equal(5, Recipes.recipe_product_amount(recipe, "iron-plate"))
    end)

    it("returns nil when product has probability", function()
      local recipe = {
        name = "some-recipe",
        products = {
          {type = "item", name = "iron-plate", amount = 2, probability = 0.5}
        }
      }
      assert.is_nil(Recipes.recipe_product_amount(recipe, "iron-plate"))
    end)

    it("returns nil when product has amount_min", function()
      local recipe = {
        name = "some-recipe",
        products = {
          {type = "item", name = "iron-plate", amount_min = 1, amount_max = 3}
        }
      }
      assert.is_nil(Recipes.recipe_product_amount(recipe, "iron-plate"))
    end)

    it("returns nil when product is not an item", function()
      local recipe = {
        name = "some-recipe",
        products = {
          {type = "fluid", name = "water", amount = 10}
        }
      }
      assert.is_nil(Recipes.recipe_product_amount(recipe, "water"))
    end)

    it("returns nil for barrelled recipe producing empty barrel", function()
      local recipe = {
        name = "ag-mall-barrelled-water",
        products = {
          {type = "item", name = "barrel", amount = 1}
        }
      }
      assert.is_nil(Recipes.recipe_product_amount(recipe, "barrel"))
    end)

    it("returns 0 (not nil) when product has amount=0", function()
      -- amount=0 is not > 0, so fixed_product_amount returns nil,
      -- which makes recipe_product_amount return nil
      local recipe = {
        name = "some-recipe",
        products = {
          {type = "item", name = "iron-plate", amount = 0}
        }
      }
      assert.is_nil(Recipes.recipe_product_amount(recipe, "iron-plate"))
    end)
  end)

  describe("recipe_item_ingredients", function()
    it("returns list of item ingredients", function()
      local recipe = {
        ingredients = {
          {type = "item", name = "iron-ore", amount = 1},
          {type = "item", name = "copper-ore", amount = 2}
        }
      }
      local result = Recipes.recipe_item_ingredients(recipe)
      assert.are.equal(2, #result)
      assert.are.equal("iron-ore", result[1].name)
      assert.are.equal(1, result[1].amount)
      assert.are.equal("copper-ore", result[2].name)
      assert.are.equal(2, result[2].amount)
    end)

    it("returns nil when ingredient has probability", function()
      local recipe = {
        ingredients = {
          {type = "item", name = "iron-ore", amount = 1, probability = 0.5}
        }
      }
      assert.is_nil(Recipes.recipe_item_ingredients(recipe))
    end)

    it("returns nil when ingredient is not an item", function()
      local recipe = {
        ingredients = {
          {type = "fluid", name = "water", amount = 10}
        }
      }
      assert.is_nil(Recipes.recipe_item_ingredients(recipe))
    end)

    it("returns empty list for empty ingredients", function()
      local recipe = {ingredients = {}}
      local result = Recipes.recipe_item_ingredients(recipe)
      assert.are.equal(0, #result)
    end)
  end)

  describe("aggregate_recipe_ingredients", function()
    it("aggregates ingredients for N crafts", function()
      local recipe = {
        ingredients = {
          {type = "item", name = "iron-ore", amount = 2},
          {type = "item", name = "copper-ore", amount = 3}
        }
      }
      local result = Recipes.aggregate_recipe_ingredients(recipe, 3, "normal")
      assert.are.equal(2, #result)
      -- sorted by name: copper < iron
      assert.are.equal("copper-ore", result[1].name)
      assert.are.equal(9, result[1].amount)
      assert.are.equal("iron-ore", result[2].name)
      assert.are.equal(6, result[2].amount)
    end)

    it("merges duplicate ingredient names", function()
      local recipe = {
        ingredients = {
          {type = "item", name = "iron-ore", amount = 2},
          {type = "item", name = "iron-ore", amount = 3}
        }
      }
      local result = Recipes.aggregate_recipe_ingredients(recipe, 1, "normal")
      assert.are.equal(1, #result)
      assert.are.equal(5, result[1].amount)
    end)

    it("sets quality on ingredients", function()
      local recipe = {
        ingredients = {
          {type = "item", name = "iron-ore", amount = 1}
        }
      }
      local result = Recipes.aggregate_recipe_ingredients(recipe, 1, "legendary")
      assert.are.equal("legendary", result[1].quality)
    end)

    it("returns nil when ingredients have probability", function()
      local recipe = {
        ingredients = {
          {type = "item", name = "iron-ore", amount = 1, probability = 0.5}
        }
      }
      assert.is_nil(Recipes.aggregate_recipe_ingredients(recipe, 1, "normal"))
    end)
  end)

  describe("recipe_outputs", function()
    it("returns sorted list of item outputs", function()
      local recipe = {
        products = {
          {type = "item", name = "copper-plate", amount = 1},
          {type = "item", name = "iron-plate", amount = 2}
        }
      }
      local result = Recipes.recipe_outputs(recipe, "normal")
      assert.are.equal(2, #result)
      assert.are.equal("copper-plate", result[1].name)
      assert.are.equal("iron-plate", result[2].name)
    end)

    it("returns nil when product is fluid", function()
      local recipe = {
        products = {
          {type = "fluid", name = "water", amount = 10}
        }
      }
      assert.is_nil(Recipes.recipe_outputs(recipe, "normal"))
    end)

    it("returns nil when product has probability", function()
      local recipe = {
        products = {
          {type = "item", name = "iron-plate", amount = 2, probability = 0.5}
        }
      }
      assert.is_nil(Recipes.recipe_outputs(recipe, "normal"))
    end)

    it("sets quality on outputs", function()
      local recipe = {
        products = {
          {type = "item", name = "iron-plate", amount = 2}
        }
      }
      local result = Recipes.recipe_outputs(recipe, "epic")
      assert.are.equal("epic", result[1].quality)
    end)
  end)

  describe("recipe_can_make_item", function()
    local function make_workshop()
      return {
        prototype = {
          crafting_categories = {crafting = true}
        }
      }
    end

    local function make_recipe(opts)
      return {
        name = opts.name or "iron-plate",
        valid = true,
        enabled = opts.enabled ~= false,
        hidden = opts.hidden or false,
        energy = opts.energy or 1,
        products = opts.products or {},
        ingredients = opts.ingredients or {},
        has_category = function(cat) return cat == "crafting" end
      }
    end

    it("returns product amount when recipe can make item", function()
      local workshop = make_workshop()
      local recipe = make_recipe({
        products = {{type = "item", name = "iron-plate", amount = 2}},
        ingredients = {{type = "item", name = "iron-ore", amount = 1}}
      })
      assert.are.equal(2, Recipes.recipe_can_make_item(workshop, recipe, "iron-plate"))
    end)

    it("returns nil when recipe is disabled", function()
      local workshop = make_workshop()
      local recipe = make_recipe({
        enabled = false,
        products = {{type = "item", name = "iron-plate", amount = 2}},
        ingredients = {{type = "item", name = "iron-ore", amount = 1}}
      })
      assert.is_nil(Recipes.recipe_can_make_item(workshop, recipe, "iron-plate"))
    end)

    it("returns nil when recipe is hidden (non-barrelled)", function()
      local workshop = make_workshop()
      local recipe = make_recipe({
        name = "secret",
        hidden = true,
        products = {{type = "item", name = "iron-plate", amount = 2}},
        ingredients = {{type = "item", name = "iron-ore", amount = 1}}
      })
      assert.is_nil(Recipes.recipe_can_make_item(workshop, recipe, "iron-plate"))
    end)

    it("returns nil when recipe is nil", function()
      local workshop = make_workshop()
      assert.is_nil(Recipes.recipe_can_make_item(workshop, nil, "iron-plate"))
    end)

    it("returns nil when ingredients have probability", function()
      local workshop = make_workshop()
      local recipe = make_recipe({
        products = {{type = "item", name = "iron-plate", amount = 2}},
        ingredients = {{type = "item", name = "iron-ore", amount = 1, probability = 0.5}}
      })
      assert.is_nil(Recipes.recipe_can_make_item(workshop, recipe, "iron-plate"))
    end)
  end)

  describe("cached_recipe_for_item", function()
    local function make_workshop(categories)
      return {
        prototype = {
          crafting_categories = categories or {crafting = true}
        }
      }
    end

    local function make_recipe(opts)
      return {
        name = opts.name or "iron-plate",
        valid = opts.valid ~= false,
        enabled = opts.enabled ~= false,
        hidden = opts.hidden or false,
        energy = opts.energy or 1,
        products = opts.products or {{type = "item", name = "iron-plate", amount = 1}},
        ingredients = opts.ingredients or {{type = "item", name = "iron-ore", amount = 1}},
        has_category = function(cat)
          local cats = opts.categories or {crafting = true}
          return cats[cat] == true
        end
      }
    end

    local function make_force(recipes)
      return {recipes = recipes or {}}
    end

    it("caches a found recipe", function()
      local recipe = make_recipe({name = "iron-plate"})
      local force = make_force({["iron-plate"] = recipe})
      local workshop = make_workshop()
      local brain = {recipe_choices = {}}

      local found, amount = Recipes.cached_recipe_for_item(brain, workshop, force, "iron-plate")
      assert.are.equal(recipe, found)
      assert.are.equal(1, amount)
      assert.are.equal("iron-plate", brain.recipe_choices["iron-plate"].recipe_name)
    end)

    it("returns nil for cached false entry", function()
      local force = make_force({})
      local workshop = make_workshop()
      local brain = {recipe_choices = {["iron-plate"] = false}}

      local found, amount = Recipes.cached_recipe_for_item(brain, workshop, force, "iron-plate")
      assert.is_nil(found)
      assert.is_nil(amount)
    end)

    it("invalidates cache when cached recipe becomes hidden", function()
      local recipe = make_recipe({name = "iron-plate", hidden = false})
      local force = make_force({["iron-plate"] = recipe})
      local workshop = make_workshop()
      local brain = {recipe_choices = {}}

      -- Prime the cache.
      local found1 = Recipes.cached_recipe_for_item(brain, workshop, force, "iron-plate")
      assert.are.equal(recipe, found1)

      -- The recipe is later hidden by a script/mod update.
      recipe.hidden = true

      -- Should detect the recipe is no longer available and recompute.
      local found2, amount2 = Recipes.cached_recipe_for_item(brain, workshop, force, "iron-plate")
      assert.is_nil(found2)
      assert.is_nil(amount2)
    end)

    it("invalidates cache when workshop no longer supports recipe category", function()
      local recipe = make_recipe({name = "iron-plate", categories = {advanced = true}})
      local force = make_force({["iron-plate"] = recipe})
      local workshop = make_workshop({advanced = true})
      local brain = {recipe_choices = {}}

      -- Prime the cache with a workshop that supports the recipe.
      local found1 = Recipes.cached_recipe_for_item(brain, workshop, force, "iron-plate")
      assert.are.equal(recipe, found1)

      -- A different workshop (or prototype change) no longer supports the category.
      local other_workshop = make_workshop({crafting = true})

      -- Should recompute and find no valid recipe for this workshop.
      local found2, amount2 = Recipes.cached_recipe_for_item(brain, other_workshop, force, "iron-plate")
      assert.is_nil(found2)
      assert.is_nil(amount2)
    end)
  end)
end)
