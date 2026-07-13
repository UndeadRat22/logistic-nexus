-- AG Mall
-- Pure utility functions with no Factorio API dependency.
-- These are the primary unit-test targets.

local M = {}

------------------------------------------------------------
-- QUALITY / ITEM KEY HELPERS
------------------------------------------------------------

function M.quality_name(quality)
  if type(quality) == "string" then
    return quality
  end

  if quality and quality.name then
    return quality.name
  end

  return "normal"
end

function M.item_key(name, quality)
  return name .. "|" .. M.quality_name(quality)
end

function M.split_item_key(key)
  local name, quality = string.match(key, "^(.*)|([^|]+)$")
  return name or key, quality or "normal"
end

function M.item_id(name, quality)
  quality = M.quality_name(quality)

  if quality == "normal" then
    return name
  end

  return {
    name = name,
    quality = quality
  }
end

------------------------------------------------------------
-- AMOUNT HELPERS
------------------------------------------------------------

function M.fixed_product_amount(product)
  if product.amount and product.amount > 0 then
    return product.amount
  end

  return nil
end

function M.fixed_ingredient_amount(ingredient)
  if ingredient
      and ingredient.amount
      and ingredient.amount > 0
      and not ingredient.probability
      and not ingredient.amount_min
      and not ingredient.amount_max then
    return ingredient.amount
  end

  return nil
end

function M.ingredient_count(ingredient)
  local amount = M.fixed_ingredient_amount(ingredient)
  return amount and math.ceil(amount) or nil
end

------------------------------------------------------------
-- COUNT / INGREDIENT CONVERSION
------------------------------------------------------------

function M.add_count(counts, name, amount, quality)
  if not (name and amount and amount > 0) then
    return
  end

  local key = M.item_key(name, quality)
  counts[key] = (counts[key] or 0) + amount
end

function M.counts_to_ingredients(counts)
  local ingredients = {}

  for key, amount in pairs(counts or {}) do
    if amount > 0 then
      local name, quality = M.split_item_key(key)
      table.insert(ingredients, {
        name = name,
        quality = quality,
        amount = amount
      })
    end
  end

  table.sort(ingredients, function(a, b)
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.quality < b.quality
  end)

  return ingredients
end

function M.copy_counts(counts)
  local copy = {}
  for name, count in pairs(counts or {}) do
    copy[name] = count
  end
  return copy
end

------------------------------------------------------------
-- STACK / POSITION HELPERS
------------------------------------------------------------

function M.stack_definition(name, count, quality)
  quality = M.quality_name(quality)

  local stack = {
    name = name,
    count = count
  }

  if quality and quality ~= "normal" then
    stack.quality = quality
  end

  return stack
end

function M.position_key(position)
  return position.x .. "," .. position.y
end

------------------------------------------------------------
-- SORT FUNCTIONS
------------------------------------------------------------

function M.shortage_sort(a, b)
  local priority_a = a.priority or 1
  local priority_b = b.priority or 1

  if priority_a ~= priority_b then
    return priority_a > priority_b
  end

  if a.missing ~= b.missing then
    return a.missing > b.missing
  end

  return a.name < b.name
end

------------------------------------------------------------
-- KEY GENERATORS
------------------------------------------------------------

function M.brain_key(network)
  return network.force.name .. "|" .. network.network_id
end

function M.construction_reservation_key(network, name, quality)
  return network.network_id .. "|" .. M.item_key(name, quality)
end

function M.construction_scan_key(surface_index, force_name, network_id)
  return surface_index .. "|" .. force_name .. "|" .. network_id
end

------------------------------------------------------------
-- STATUS DISPLAY HELPER
------------------------------------------------------------

function M.status_item_name(name, quality)
  if not name then
    return ""
  end

  quality = M.quality_name(quality)
  if quality == "normal" then
    return name
  end

  return name .. "@" .. quality
end

return M
