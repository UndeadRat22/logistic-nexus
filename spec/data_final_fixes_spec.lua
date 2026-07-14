local helpers = require("spec.helpers")

helpers.install_globals()
helpers.install_data_stage_util()
helpers.install_table_deepcopy()

local function reset_data()
  helpers.make_data_raw()
  helpers.make_settings()
  package.loaded["prototypes.entity"] = nil
  package.loaded["prototypes.data_stage_util"] = nil
  package.loaded["data-final-fixes"] = nil
end

describe("data-final-fixes category collection", function()
  before_each(function()
    reset_data()
  end)

  it("adds mod recipe categories to both workshop tiers", function()
    require("prototypes.entity")
    require("data-final-fixes")

    local workshop = data.raw["assembling-machine"]["logistic-nexus-workshop"]
    local mk2 = data.raw["assembling-machine"]["logistic-nexus-workshop-mk2"]

    assert.is_not_nil(workshop)
    assert.is_not_nil(mk2)

    assert.is_true(helpers.has_category(workshop, "pressing"),
      "base workshop should support pressing category")
    assert.is_true(helpers.has_category(mk2, "pressing"),
      "MK2 workshop should support pressing category")
  end)

  it("respects excluded categories", function()
    settings.startup["logistic-nexus-excluded-categories"].value = "pressing"

    require("prototypes.entity")
    require("data-final-fixes")

    local workshop = data.raw["assembling-machine"]["logistic-nexus-workshop"]
    local mk2 = data.raw["assembling-machine"]["logistic-nexus-workshop-mk2"]

    assert.is_false(helpers.has_category(workshop, "pressing"))
    assert.is_false(helpers.has_category(mk2, "pressing"))
  end)

  it("collects alternate recipe categories", function()
    data.raw.recipe["transport-belt"].categories = {"crafting"}
    data.raw.recipe["transport-belt"].categories = {"crafting", "pressing"}

    require("prototypes.entity")
    require("data-final-fixes")

    local workshop = data.raw["assembling-machine"]["logistic-nexus-workshop"]

    assert.is_true(helpers.has_category(workshop, "pressing"))
  end)

  it("inherits categories updated on the base assembling machine", function()
    -- Simulate Space Age updating assembling-machine-3 after our prototype was copied.
    data.raw["assembling-machine"]["assembling-machine-3"].crafting_categories = {
      "crafting",
      "pressing",
      "metallurgy"
    }

    require("prototypes.entity")
    require("data-final-fixes")

    local workshop = data.raw["assembling-machine"]["logistic-nexus-workshop"]

    assert.is_true(helpers.has_category(workshop, "pressing"))
    assert.is_true(helpers.has_category(workshop, "metallurgy"))
  end)

  it("collects categories defined in set/map format", function()
    -- Simulate a mod that defines crafting_categories as a set (keys = true).
    data.raw.recipe["transport-belt"].categories = nil
    data.raw.recipe["transport-belt"].categories = nil
    data.raw["assembling-machine"]["assembling-machine-3"].crafting_categories = {
      crafting = true,
      pressing = true
    }

    require("prototypes.entity")
    require("data-final-fixes")

    local workshop = data.raw["assembling-machine"]["logistic-nexus-workshop"]

    assert.is_true(helpers.has_category(workshop, "crafting"),
      "should collect set-key category 'crafting'")
    assert.is_true(helpers.has_category(workshop, "pressing"),
      "should collect set-key category 'pressing'")
  end)
end)
