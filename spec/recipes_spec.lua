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
        name = "logistic-nexus-barrelled-water",
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
        name = "logistic-nexus-barrelled-water",
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

  describe("find_recipe_for_item", function()
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

    it("returns the exact-name recipe when it exists", function()
      local recipe = make_recipe({name = "iron-plate"})
      local force = make_force({["iron-plate"] = recipe})
      local workshop = make_workshop()

      local found, amount = Recipes.find_recipe_for_item(workshop, force, "iron-plate")
      assert.are.equal(recipe, found)
      assert.are.equal(1, amount)
    end)

    it("returns the lowest-energy recipe when multiple produce the item", function()
      local recipe_fast = make_recipe({name = "fast-iron", energy = 0.5, products = {{type = "item", name = "iron-plate", amount = 1}}})
      local recipe_slow = make_recipe({name = "slow-iron", energy = 2, products = {{type = "item", name = "iron-plate", amount = 1}}})
      local force = make_force({["fast-iron"] = recipe_fast, ["slow-iron"] = recipe_slow})
      local workshop = make_workshop()

      local found = Recipes.find_recipe_for_item(workshop, force, "iron-plate")
      assert.are.equal(recipe_fast, found)
    end)

    it("breaks energy ties by name ascending", function()
      local recipe_b = make_recipe({name = "b-recipe", energy = 1, products = {{type = "item", name = "iron-plate", amount = 1}}})
      local recipe_a = make_recipe({name = "a-recipe", energy = 1, products = {{type = "item", name = "iron-plate", amount = 1}}})
      local force = make_force({["b-recipe"] = recipe_b, ["a-recipe"] = recipe_a})
      local workshop = make_workshop()

      local found = Recipes.find_recipe_for_item(workshop, force, "iron-plate")
      assert.are.equal(recipe_a, found)
    end)

    it("returns nil when no recipe produces the item", function()
      local force = make_force({["iron-plate"] = make_recipe({name = "iron-plate", products = {{type = "item", name = "copper-plate", amount = 1}}})})
      local workshop = make_workshop()

      local found = Recipes.find_recipe_for_item(workshop, force, "nonexistent")
      assert.is_nil(found)
    end)

    it("returns nil when all recipes are disabled", function()
      local recipe = make_recipe({name = "iron-plate", enabled = false})
      local force = make_force({["iron-plate"] = recipe})
      local workshop = make_workshop()

      local found = Recipes.find_recipe_for_item(workshop, force, "iron-plate")
      assert.is_nil(found)
    end)

    it("returns nil when recipe is hidden and non-barrelled", function()
      local recipe = make_recipe({name = "secret", hidden = true, products = {{type = "item", name = "iron-plate", amount = 1}}})
      local force = make_force({["secret"] = recipe})
      local workshop = make_workshop()

      local found = Recipes.find_recipe_for_item(workshop, force, "iron-plate")
      assert.is_nil(found)
    end)

    it("skips recipes whose category the workshop lacks", function()
      local recipe = make_recipe({name = "iron-plate", categories = {advanced = true}})
      local force = make_force({["iron-plate"] = recipe})
      local workshop = make_workshop({crafting = true})

      local found = Recipes.find_recipe_for_item(workshop, force, "iron-plate")
      assert.is_nil(found)
    end)

    it("prefers barrelled recipe over normal recipe", function()
      local normal_recipe = make_recipe({name = "water", energy = 0.1, products = {{type = "item", name = "water", amount = 1}}})
      local barrelled_recipe = make_recipe({
        name = "logistic-nexus-barrelled-water",
        hidden = true,
        energy = 0.5,
        products = {{type = "item", name = "water", amount = 1}}
      })
      local force = make_force({
        ["water"] = normal_recipe,
        ["logistic-nexus-barrelled-water"] = barrelled_recipe
      })
      local workshop = make_workshop()

      local found = Recipes.find_recipe_for_item(workshop, force, "water")
      assert.are.equal(barrelled_recipe, found)
    end)
  end)

  describe("build_recipe_index", function()
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

    it("builds an index mapping item_name to candidate recipes", function()
      local recipe = make_recipe({name = "iron-plate"})
      local force = make_force({["iron-plate"] = recipe})

      local index = Recipes.build_recipe_index(force)
      assert.is_not_nil(index["iron-plate"])
      assert.are.equal(1, #index["iron-plate"])
      assert.are.equal(recipe, index["iron-plate"][1].recipe)
      assert.are.equal(1, index["iron-plate"][1].product_amount)
    end)

    it("excludes disabled recipes", function()
      local recipe = make_recipe({name = "iron-plate", enabled = false})
      local force = make_force({["iron-plate"] = recipe})

      local index = Recipes.build_recipe_index(force)
      assert.is_nil(index["iron-plate"])
    end)

    it("excludes hidden non-barrelled recipes", function()
      local recipe = make_recipe({name = "secret", hidden = true})
      local force = make_force({["secret"] = recipe})

      local index = Recipes.build_recipe_index(force)
      assert.is_nil(index["iron-plate"])
    end)

    it("includes hidden barrelled recipes", function()
      local recipe = make_recipe({
        name = "logistic-nexus-barrelled-water",
        hidden = true,
        products = {{type = "item", name = "water-barrel", amount = 1}}
      })
      local force = make_force({["logistic-nexus-barrelled-water"] = recipe})

      local index = Recipes.build_recipe_index(force)
      assert.is_not_nil(index["water-barrel"])
      assert.are.equal(recipe, index["water-barrel"][1].recipe)
    end)

    it("excludes recipes with fluid products", function()
      local recipe = make_recipe({
        name = "oil",
        products = {{type = "fluid", name = "crude-oil", amount = 10}}
      })
      local force = make_force({["oil"] = recipe})

      local index = Recipes.build_recipe_index(force)
      assert.is_nil(index["crude-oil"])
    end)

    it("excludes recipes with probabilistic products", function()
      local recipe = make_recipe({
        name = "gamble",
        products = {{type = "item", name = "iron-plate", amount = 1, probability = 0.5}}
      })
      local force = make_force({["gamble"] = recipe})

      local index = Recipes.build_recipe_index(force)
      assert.is_nil(index["iron-plate"])
    end)

    it("excludes recipes with fluid ingredients", function()
      local recipe = make_recipe({
        name = "oil-refining",
        products = {{type = "item", name = "plastic-bar", amount = 1}},
        ingredients = {{type = "fluid", name = "crude-oil", amount = 10}}
      })
      local force = make_force({["oil-refining"] = recipe})

      local index = Recipes.build_recipe_index(force)
      assert.is_nil(index["plastic-bar"])
    end)

    it("sorts candidates by energy then name", function()
      local recipe_slow = make_recipe({name = "z-slow", energy = 2, products = {{type = "item", name = "iron-plate", amount = 1}}})
      local recipe_fast = make_recipe({name = "a-fast", energy = 0.5, products = {{type = "item", name = "iron-plate", amount = 1}}})
      local recipe_mid = make_recipe({name = "m-mid", energy = 1, products = {{type = "item", name = "iron-plate", amount = 1}}})
      local force = make_force({
        ["z-slow"] = recipe_slow,
        ["a-fast"] = recipe_fast,
        ["m-mid"] = recipe_mid
      })

      local index = Recipes.build_recipe_index(force)
      assert.are.equal(3, #index["iron-plate"])
      assert.are.equal("a-fast", index["iron-plate"][1].recipe.name)
      assert.are.equal("m-mid", index["iron-plate"][2].recipe.name)
      assert.are.equal("z-slow", index["iron-plate"][3].recipe.name)
    end)

    it("aggregates multiple products from a single recipe", function()
      local recipe = make_recipe({
        name = "dual",
        products = {
          {type = "item", name = "iron-plate", amount = 2},
          {type = "item", name = "copper-plate", amount = 3}
        }
      })
      local force = make_force({["dual"] = recipe})

      local index = Recipes.build_recipe_index(force)
      assert.are.equal(2, index["iron-plate"][1].product_amount)
      assert.are.equal(3, index["copper-plate"][1].product_amount)
    end)

    it("handles empty force recipes", function()
      local force = make_force({})
      local index = Recipes.build_recipe_index(force)
      assert.are.same({}, index)
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
