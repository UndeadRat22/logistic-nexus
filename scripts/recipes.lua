-- Logistic Nexus
-- Recipe validation, finding, and caching.

local C = require("scripts.constants")
local Util = require("scripts.util")

local M = {}

------------------------------------------------------------
-- RECIPE VALIDATION
------------------------------------------------------------

function M.recipe_has_supported_category(workshop, recipe)
  local categories = workshop.prototype and workshop.prototype.crafting_categories
  if not categories then
    return false
  end

  for key, value in pairs(categories) do
    local category = type(key) == "string" and key or value
    if type(category) == "string" and recipe.has_category(category) then
      return true
    end
  end

  return false
end

function M.recipe_is_available_to_mall(recipe)
  return not recipe.hidden
      or string.sub(recipe.name, 1, #C.BARRELLED_RECIPE_PREFIX) == C.BARRELLED_RECIPE_PREFIX
end

function M.recipe_product_amount(recipe, item_name)
  if item_name == C.EMPTY_BARREL_ITEM
      and string.sub(recipe.name, 1, #C.BARRELLED_RECIPE_PREFIX) == C.BARRELLED_RECIPE_PREFIX then
    return nil
  end

  local amount = nil

  for _, product in pairs(recipe.products or {}) do
    if product.type == "item" and product.name == item_name then
      local product_amount = Util.fixed_product_amount(product)
      if not product_amount then
        return nil
      end

      amount = (amount or 0) + product_amount
    elseif product.type ~= "item" then
      return nil
    end
  end

  return amount
end

function M.recipe_item_ingredients(recipe)
  local ingredients = {}

  for _, ingredient in pairs(recipe.ingredients or {}) do
    local amount = Util.fixed_ingredient_amount(ingredient)

    if ingredient.type ~= "item" or not amount then
      return nil
    end

    table.insert(ingredients, {
      name = ingredient.name,
      amount = amount
    })
  end

  return ingredients
end

function M.recipe_can_make_item(workshop, recipe, item_name)
  if not (recipe
      and recipe.valid
      and recipe.enabled
      and M.recipe_is_available_to_mall(recipe)
      and M.recipe_has_supported_category(workshop, recipe)) then
    return nil
  end

  local product_amount = M.recipe_product_amount(recipe, item_name)
  if product_amount and M.recipe_item_ingredients(recipe) then
    return product_amount
  end

  return nil
end

------------------------------------------------------------
-- RECIPE INDEX
--
-- A reverse index mapping item_name → sorted list of candidate recipes.
-- Built once per force (or on research changes) so that recipe lookup is
-- O(candidates_for_item) instead of O(all_recipes).
------------------------------------------------------------

local function recipe_is_indexable(recipe)
  if not (recipe and recipe.valid and recipe.enabled) then
    return false
  end

  if not M.recipe_is_available_to_mall(recipe) then
    return false
  end

  local ingredients = M.recipe_item_ingredients(recipe)
  if not ingredients then
    return false
  end

  return true
end

function M.build_recipe_index(force)
  local index = {}

  for _, recipe in pairs(force.recipes or {}) do
    if recipe_is_indexable(recipe) then
      for _, product in pairs(recipe.products or {}) do
        if product.type == "item" then
          local amount = Util.fixed_product_amount(product)
          if amount then
            local name = product.name
            if not index[name] then
              index[name] = {}
            end
            table.insert(index[name], {
              recipe = recipe,
              product_amount = amount
            })
          end
        end
      end
    end
  end

  for _, candidates in pairs(index) do
    table.sort(candidates, function(a, b)
      if a.recipe.energy ~= b.recipe.energy then
        return a.recipe.energy < b.recipe.energy
      end
      return a.recipe.name < b.recipe.name
    end)
  end

  return index
end

------------------------------------------------------------
-- RECIPE FINDING
------------------------------------------------------------

function M.ensure_direct_barrelled_recipe(force, item_name)
  local recipe = force.recipes[C.BARRELLED_RECIPE_PREFIX .. item_name]
  local source_recipe = force.recipes[item_name]

  if recipe and source_recipe and source_recipe.enabled then
    recipe.enabled = true
  end

  return recipe
end

function M.get_recipe_index(force)
  if not (force and force.name) then
    return nil
  end

  if type(storage.recipe_indexes) ~= "table" then
    storage.recipe_indexes = {}
  end

  local key = force.name
  local index = storage.recipe_indexes[key]

  if not index then
    index = M.build_recipe_index(force)
    storage.recipe_indexes[key] = index
  end

  return index
end

function M.invalidate_recipe_index(force)
  if type(storage.recipe_indexes) ~= "table" then
    return
  end

  if force then
    storage.recipe_indexes[force.name] = nil
  else
    storage.recipe_indexes = {}
  end
end

function M.find_recipe_for_item(workshop, force, item_name)
  local best_recipe = nil
  local best_product_amount = nil
  local barrelled_recipe = M.ensure_direct_barrelled_recipe(force, item_name)
  local barrelled_amount = M.recipe_can_make_item(workshop, barrelled_recipe, item_name)

  if barrelled_amount then
    return barrelled_recipe, barrelled_amount
  end

  local index = M.get_recipe_index(force)
  local candidates = index and index[item_name]

  if candidates then
    for _, entry in ipairs(candidates) do
      local product_amount = M.recipe_can_make_item(workshop, entry.recipe, item_name)
      if product_amount then
        if entry.recipe.name == item_name then
          return entry.recipe, product_amount
        end

        if not best_recipe
            or entry.recipe.energy < best_recipe.energy
            or (entry.recipe.energy == best_recipe.energy and entry.recipe.name < best_recipe.name) then
          best_recipe = entry.recipe
          best_product_amount = product_amount
        end
      end
    end
  else
    for _, recipe in pairs(force.recipes) do
      local product_amount = M.recipe_can_make_item(workshop, recipe, item_name)

      if product_amount then
        if recipe.name == item_name then
          return recipe, product_amount
        end

        if not best_recipe
            or recipe.energy < best_recipe.energy
            or (recipe.energy == best_recipe.energy and recipe.name < best_recipe.name) then
          best_recipe = recipe
          best_product_amount = product_amount
        end
      end
    end
  end

  return best_recipe, best_product_amount
end

function M.cached_recipe_for_item(brain, workshop, force, item_name)
  if not brain then
    return M.find_recipe_for_item(workshop, force, item_name)
  end

  local cached = brain.recipe_choices[item_name]
  if cached ~= nil then
    if cached == false then
      return nil, nil
    end

    local recipe = force.recipes[cached.recipe_name]
    if recipe
        and recipe.valid
        and recipe.enabled
        and M.recipe_is_available_to_mall(recipe)
        and M.recipe_has_supported_category(workshop, recipe) then
      return recipe, cached.product_amount
    end
  end

  local recipe, product_amount = M.find_recipe_for_item(workshop, force, item_name)
  if recipe then
    brain.recipe_choices[item_name] = {
      recipe_name = recipe.name,
      product_amount = product_amount
    }
  else
    brain.recipe_choices[item_name] = false
  end

  return recipe, product_amount
end

------------------------------------------------------------
-- RECIPE AGGREGATION
------------------------------------------------------------

function M.aggregate_recipe_ingredients(recipe, crafts, quality)
  local ingredients = M.recipe_item_ingredients(recipe)
  if not ingredients then
    return nil
  end
  quality = Util.quality_name(quality)

  local by_name = {}

  for _, ingredient in pairs(ingredients) do
    local entry = by_name[ingredient.name]
    if not entry then
      entry = {
        name = ingredient.name,
        quality = quality,
        amount = 0
      }
      by_name[ingredient.name] = entry
    end

    entry.amount = entry.amount + ingredient.amount * crafts
  end

  local result = {}

  for _, ingredient in pairs(by_name) do
    table.insert(result, ingredient)
  end

  table.sort(result, function(a, b)
    return a.name < b.name
  end)

  return result
end

function M.recipe_outputs(recipe, quality)
  local outputs = {}
  quality = Util.quality_name(quality)

  for _, product in pairs(recipe.products or {}) do
    if product.type ~= "item" then
      return nil
    end

    local amount = Util.fixed_product_amount(product)
    if not amount then
      return nil
    end

    table.insert(outputs, {
      name = product.name,
      quality = quality,
      amount = amount
    })
  end

  table.sort(outputs, function(a, b)
    return a.name < b.name
  end)

  return outputs
end

return M
