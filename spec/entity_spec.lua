local helpers = require("spec.helpers")

helpers.install_globals()
helpers.install_data_stage_util()
helpers.install_table_deepcopy()

local function reset_data(modules_enabled)
  helpers.make_data_raw()
  _G.settings = {
    startup = {
      ["logistic-nexus-enable-modules"] = {value = modules_enabled == true}
    }
  }
end

describe("workshop entity prototype", function()
  before_each(function()
    reset_data()
    package.loaded["prototypes.entity"] = nil
  end)

  it("enables module slots and effects when setting is on", function()
    reset_data(true)
    package.loaded["prototypes.entity"] = nil
    require("prototypes.entity")

    local workshop = data.raw["assembling-machine"]["logistic-nexus-workshop"]
    assert.is_not_nil(workshop)
    assert.are.equal(4, workshop.module_slots)
    assert.are.same({"consumption", "speed", "productivity", "pollution"}, workshop.allowed_effects)
  end)

  it("disables module slots by default", function()
    reset_data(false)
    package.loaded["prototypes.entity"] = nil
    require("prototypes.entity")

    local workshop = data.raw["assembling-machine"]["logistic-nexus-workshop"]
    assert.is_not_nil(workshop)
    assert.are.equal(0, workshop.module_slots)
    assert.are.same({}, workshop.allowed_effects)
  end)

  it("allows blueprint copy-paste", function()
    require("prototypes.entity")

    local workshop = data.raw["assembling-machine"]["logistic-nexus-workshop"]
    assert.is_not_nil(workshop)
    assert.is_true(workshop.allow_copy_paste)

    local mk2 = data.raw["assembling-machine"]["logistic-nexus-workshop-mk2"]
    assert.is_not_nil(mk2)
    assert.is_true(mk2.allow_copy_paste)
  end)

  it("creates an MK2 tier with faster speed and more module slots", function()
    reset_data(true)
    package.loaded["prototypes.entity"] = nil
    require("prototypes.entity")

    local mk2 = data.raw["assembling-machine"]["logistic-nexus-workshop-mk2"]
    assert.is_not_nil(mk2)
    assert.are.equal(2, mk2.crafting_speed)
    assert.are.equal(6, mk2.module_slots)
    assert.are.equal("1500kW", mk2.energy_usage)
    assert.is_nil(mk2.next_upgrade)

    local base = data.raw["assembling-machine"]["logistic-nexus-workshop"]
    assert.are.equal("logistic-nexus-workshop-mk2", base.next_upgrade)
  end)

  it("shares fast_replaceable_group between tiers so next_upgrade is valid", function()
    require("prototypes.entity")

    local base = data.raw["assembling-machine"]["logistic-nexus-workshop"]
    local mk2 = data.raw["assembling-machine"]["logistic-nexus-workshop-mk2"]
    assert.are.equal("logistic-nexus-workshop", base.fast_replaceable_group)
    assert.are.equal(base.fast_replaceable_group, mk2.fast_replaceable_group)
  end)
end)
