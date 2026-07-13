-- Logistic Nexus
-- Data stage entry point.

require("prototypes.entity")
require("prototypes.item")
require("prototypes.recipe")

local unlock_tech = data.raw.technology["logistic-system"] or data.raw.technology["automation-3"]
local recipe = data.raw.recipe["logistic-nexus-workshop"]

if unlock_tech and recipe then
  unlock_tech.effects = unlock_tech.effects or {}
  table.insert(unlock_tech.effects, {
    type = "unlock-recipe",
    recipe = "logistic-nexus-workshop"
  })
elseif recipe then
  recipe.enabled = true
end

local mk2_recipe = data.raw.recipe["logistic-nexus-workshop-mk2"]
if mk2_recipe then
  local mk2_tech = data.raw.technology["logistic-nexus-workshop-mk2"]
  if not mk2_tech then
    mk2_tech = {
      type = "technology",
      name = "logistic-nexus-workshop-mk2",
      localised_name = {"technology-name.logistic-nexus-workshop-mk2"},
      localised_description = {"technology-description.logistic-nexus-workshop-mk2"},
      icon = "__logistic-nexus__/graphics/icons/logistic-nexus-workshop.png",
      icon_size = 64,
      prerequisites = {"logistic-system"},
      effects = {
        {
          type = "unlock-recipe",
          recipe = "logistic-nexus-workshop-mk2"
        }
      },
      unit = {
        count = 500,
        ingredients = {
          {"automation-science-pack", 1},
          {"logistic-science-pack", 1},
          {"chemical-science-pack", 1},
          {"utility-science-pack", 1}
        },
        time = 30
      },
      order = "c-k-d-z"
    }
    data:extend({mk2_tech})
  else
    mk2_tech.effects = mk2_tech.effects or {}
    table.insert(mk2_tech.effects, {
      type = "unlock-recipe",
      recipe = "logistic-nexus-workshop-mk2"
    })
  end
end
