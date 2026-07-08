-- AG Mall
-- Data stage entry point.

require("prototypes.entity")
require("prototypes.item")
require("prototypes.recipe")

local unlock_tech = data.raw.technology["logistic-system"] or data.raw.technology["automation-3"]
local recipe = data.raw.recipe["ag-mall-workshop"]

if unlock_tech and recipe then
  unlock_tech.effects = unlock_tech.effects or {}
  table.insert(unlock_tech.effects, {
    type = "unlock-recipe",
    recipe = "ag-mall-workshop"
  })
elseif recipe then
  recipe.enabled = true
end
