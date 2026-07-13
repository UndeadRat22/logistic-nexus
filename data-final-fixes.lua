-- Logistic Nexus
-- Generate item-only recipe variants for recipes that normally need fluids.

local DataStageUtil = require("prototypes.data_stage_util")

local PREFIX = "logistic-nexus-barrelled-"
local BARREL_SIZE = 50
local EMPTY_BARREL_ITEM = "barrel"
local MAX_BARREL_BATCH = 1000
local EPSILON = 0.000001

local function starts_with(value, prefix)
  return string.sub(value, 1, #prefix) == prefix
end

local function normalize_ingredient(ingredient)
  return {
    type = ingredient.type or "item",
    name = ingredient.name or ingredient[1],
    amount = ingredient.amount or ingredient[2] or 1
  }
end

local function normalize_product(product)
  return {
    type = product.type or "item",
    name = product.name or product[1],
    amount = product.amount or product[2] or 1,
    probability = product.probability,
    amount_min = product.amount_min,
    amount_max = product.amount_max
  }
end

local function recipe_ingredients(recipe)
  return recipe.ingredients or {}
end

local function recipe_results(recipe)
  if recipe.results then
    return recipe.results
  end

  if recipe.result then
    return {
      {
        type = "item",
        name = recipe.result,
        amount = recipe.result_count or 1
      }
    }
  end

  return {}
end

local function add_item_amount(items, name, amount)
  if not (name and amount and amount > 0) then
    return
  end

  items[name] = (items[name] or 0) + amount
end

local function fixed_item_products(recipe)
  local products = {}

  for _, product in pairs(recipe_results(recipe)) do
    local normalized = normalize_product(product)

    if normalized.type ~= "item"
        or not normalized.name
        or not normalized.amount
        or normalized.probability
        or normalized.amount_min
        or normalized.amount_max then
      return nil
    end

    if normalized.name == EMPTY_BARREL_ITEM or string.match(normalized.name, "%-barrel$") then
      return nil
    end

    add_item_amount(products, normalized.name, normalized.amount)
  end

  return products
end

local function barrel_item_for_fluid(fluid_name)
  local item_name = fluid_name .. "-barrel"

  if data.raw.item[item_name] then
    return item_name
  end

  return nil
end

local function greatest_common_divisor(a, b)
  while b ~= 0 do
    a, b = b, a % b
  end
  return a
end

local function least_common_multiple(a, b)
  return a / greatest_common_divisor(a, b) * b
end

local function exact_barrel_batch_multiplier(amount)
  for multiplier = 1, MAX_BARREL_BATCH do
    local barrels = amount * multiplier / BARREL_SIZE
    if math.abs(barrels - math.floor(barrels + 0.5)) < EPSILON then
      return multiplier
    end
  end

  return nil
end

local function make_barrelled_recipe(recipe)
  if starts_with(recipe.name, PREFIX) or recipe.hidden then
    return nil
  end

  local products = fixed_item_products(recipe)
  if not products then
    return nil
  end

  local normalized_ingredients = {}
  local batch_multiplier = 1

  for _, ingredient in pairs(recipe_ingredients(recipe)) do
    local normalized = normalize_ingredient(ingredient)

    if not normalized.name or not normalized.amount then
      return nil
    end

    if normalized.type == "fluid" then
      if not barrel_item_for_fluid(normalized.name)
          or not data.raw.item[EMPTY_BARREL_ITEM] then
        return nil
      end

      local fluid_multiplier = exact_barrel_batch_multiplier(normalized.amount)
      if not fluid_multiplier then
        return nil
      end

      batch_multiplier = least_common_multiple(batch_multiplier, fluid_multiplier)
      if batch_multiplier > MAX_BARREL_BATCH then
        return nil
      end
    elseif normalized.type ~= "item" then
      return nil
    end

    table.insert(normalized_ingredients, normalized)
  end

  local ingredient_counts = {}
  local empty_barrels = 0
  local used_fluid = false

  for _, normalized in pairs(normalized_ingredients) do
    if normalized.type == "item" then
      add_item_amount(
        ingredient_counts,
        normalized.name,
        normalized.amount * batch_multiplier
      )
    elseif normalized.type == "fluid" then
      local barrel_item = barrel_item_for_fluid(normalized.name)
      local barrel_count = math.floor(
        normalized.amount * batch_multiplier / BARREL_SIZE + 0.5
      )
      add_item_amount(ingredient_counts, barrel_item, barrel_count)
      empty_barrels = empty_barrels + barrel_count
      used_fluid = true
    end
  end

  if not used_fluid then
    return nil
  end

  local ingredients = {}
  for name, amount in pairs(ingredient_counts) do
    table.insert(ingredients, {
      type = "item",
      name = name,
      amount = amount
    })
  end
  table.sort(ingredients, function(a, b)
    return a.name < b.name
  end)

  local results = {}
  for name, amount in pairs(products) do
    table.insert(results, {
      type = "item",
      name = name,
      amount = amount * batch_multiplier
    })
  end

  if empty_barrels > 0 then
    table.insert(results, {
      type = "item",
      name = EMPTY_BARREL_ITEM,
      amount = empty_barrels
    })
  end

  table.sort(results, function(a, b)
    return a.name < b.name
  end)

  local main_product = recipe.main_product
  if not (main_product and products[main_product]) then
    main_product = next(products)
  end

  return {
    type = "recipe",
    name = PREFIX .. recipe.name,
    localised_name = recipe.localised_name or {"recipe-name." .. recipe.name},
    enabled = recipe.enabled == true,
    hidden = true,
    hidden_in_factoriopedia = true,
    hide_from_player_crafting = true,
    hide_from_stats = true,
    allow_decomposition = false,
    allow_productivity = false,
    category = "crafting",
    energy_required = (recipe.energy_required or 0.5) * batch_multiplier,
    ingredients = ingredients,
    results = results,
    main_product = main_product
  }
end

local generated_by_source = {}
local generated = {}

for _, recipe in pairs(data.raw.recipe) do
  local barrelled = make_barrelled_recipe(recipe)
  if barrelled then
    generated_by_source[recipe.name] = barrelled.name
    table.insert(generated, barrelled)
  end
end

if #generated > 0 then
  data:extend(generated)
end

for _, technology in pairs(data.raw.technology) do
  local effects = technology.effects
  if effects then
    local unlocks = {}

    for _, effect in pairs(effects) do
      if effect.type == "unlock-recipe" and generated_by_source[effect.recipe] then
        unlocks[generated_by_source[effect.recipe]] = true
      end
    end

    for recipe_name in pairs(unlocks) do
      table.insert(effects, {
        type = "unlock-recipe",
        recipe = recipe_name
      })
    end
  end
end

-- Ensure the Logistic Nexus workshop can craft recipes from mod-added categories.
-- Categories are collected from every recipe so item-only mod recipes are
-- supported without requiring mod authors to patch the workshop prototype.
local function collect_categories(source, excluded_categories, categories)
  if type(source) == "string" and source ~= "" and not excluded_categories[source] then
    categories[source] = true
  elseif type(source) == "table" then
    for _, category in pairs(source) do
      collect_categories(category, excluded_categories, categories)
    end
  end
end

local function apply_category_collection(entity_name)
  local workshop = data.raw["assembling-machine"][entity_name]
  if not workshop then
    return
  end

  local setting_value = settings
      and settings.startup
      and settings.startup["logistic-nexus-excluded-categories"]
      and settings.startup["logistic-nexus-excluded-categories"].value
  local excluded_categories = DataStageUtil.parse_excluded_categories(setting_value)
  local categories = {}

  -- Keep categories already assigned to the workshop.
  collect_categories(workshop.crafting_categories, excluded_categories, categories)

  -- Collect primary and alternate categories from every recipe.
  for _, recipe in pairs(data.raw.recipe) do
    collect_categories(recipe.category or "crafting", excluded_categories, categories)
    collect_categories(recipe.categories, excluded_categories, categories)
  end

  -- Inherit categories from the base assembling machine, which Space Age and
  -- other mods may update in data-updates after our prototype was deep-copied.
  local base_machine = data.raw["assembling-machine"]["assembling-machine-3"]
  collect_categories(base_machine and base_machine.crafting_categories, excluded_categories, categories)

  local category_list = {}
  for category in pairs(categories) do
    table.insert(category_list, category)
  end
  workshop.crafting_categories = category_list
end

apply_category_collection("logistic-nexus-workshop")
apply_category_collection("logistic-nexus-workshop-mk2")
