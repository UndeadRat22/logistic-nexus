-- stack-inserter is a Space Age item; fall back to bulk-inserter (base 2.0).
local stack_inserter_name =
  (data.raw.item["stack-inserter"] and "stack-inserter")
  or "bulk-inserter"

data:extend({
  {
    type = "recipe",
    name = "logistic-nexus-workshop",
    localised_name = {"recipe-name.logistic-nexus-workshop"},
    enabled = false,
    energy_required = 10,
    ingredients = {
      {type = "item", name = "assembling-machine-1", amount = 2},
      {type = "item", name = "inserter", amount = 2},
      {type = "item", name = "requester-chest", amount = 1},
      {type = "item", name = "active-provider-chest", amount = 1},
      {type = "item", name = "electronic-circuit", amount = 5},
      {type = "item", name = "iron-plate", amount = 10},
      {type = "item", name = "pipe", amount = 2}
    },
    results = {
      {type = "item", name = "logistic-nexus-workshop", amount = 1}
    }
  },
  {
    type = "recipe",
    name = "logistic-nexus-workshop-mk2",
    localised_name = {"recipe-name.logistic-nexus-workshop-mk2"},
    enabled = false,
    energy_required = 15,
    ingredients = {
      {type = "item", name = "logistic-nexus-workshop", amount = 1},
      {type = "item", name = "assembling-machine-3", amount = 2},
      {type = "item", name = stack_inserter_name, amount = 4},
      {type = "item", name = "advanced-circuit", amount = 20},
      {type = "item", name = "steel-plate", amount = 20},
      {type = "item", name = "processing-unit", amount = 5}
    },
    results = {
      {type = "item", name = "logistic-nexus-workshop-mk2", amount = 1}
    }
  }
})
