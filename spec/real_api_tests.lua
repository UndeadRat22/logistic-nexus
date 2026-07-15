-- Real-API integration tests for Logistic Nexus.
-- These run inside a real Factorio instance via FactorioTest.
-- They exercise the actual engine: entity creation, logistic networks,
-- shortage detection, prototype data, and recipe management.

local C = require("scripts.constants")
local Storage = require("scripts.storage")
local Brain = require("scripts.brain")
local H = require("spec.real_api_helpers")

------------------------------------------------------------
-- Tests
------------------------------------------------------------

describe("real API: workshop registration", function()
  before_each(function()
    H.clean_surface()
    Storage.init_storage()
  end)

  it("creates companion chests when a workshop is built", function()
    local workshop = H.place_workshop(10, 10)
    assert.is_true(workshop ~= nil, "workshop should be created")
    assert.is_true(workshop.valid)

    local workshop_data = storage.workshops[workshop.unit_number]
    assert.is_not_nil(workshop_data, "workshop should be registered in storage")
    assert.is_not_nil(workshop_data.companions, "companions should be created")
    assert.is_not_nil(workshop_data.companions.requester, "requester should exist")
    assert.is_not_nil(workshop_data.companions.provider, "provider should exist")
    assert.are.equal(C.REQUESTER_NAME, workshop_data.companions.requester.name)
    assert.are.equal(C.PROVIDER_NAME, workshop_data.companions.provider.name)
  end)
end)

describe("real API: crafting pipeline", function()
  before_each(function()
    H.clean_surface()
    Storage.init_storage()
  end)

  it("detects a shortage and assigns a workshop to craft iron-plate", function()
    local force = H.get_force()

    local recipe = force.recipes["iron-plate"]
    if recipe and not recipe.enabled then
      recipe.enabled = true
    end

    H.place_roboport(15, 15)
    H.place_supply_chest(20, 20, {
      {name = "iron-ore", count = 100}
    })
    H.place_requester(25, 20, "iron-plate", 10)

    local workshop = H.place_workshop(10, 10)
    assert.is_true(workshop ~= nil and workshop.valid)

    Brain.assess_all_workshops()

    local workshop_data = storage.workshops[workshop.unit_number]
    local assignment = workshop_data and workshop_data.assignment

    assert.is_not_nil(assignment, "workshop should have an assignment")
    assert.are.equal("iron-plate", assignment.item)
  end)
end)

describe("real API: prototype data", function()
  before_each(function()
    H.clean_surface()
    Storage.init_storage()
  end)

  it("workshop entity has the correct crafting categories", function()
    local workshop = H.place_workshop(30, 30)

    assert.is_true(workshop.valid)
    local proto = workshop.prototype
    assert.is_not_nil(proto)
    local categories = proto.crafting_categories
    assert.is_not_nil(categories)
    assert.is_true(categories["crafting"] ~= nil, "should have 'crafting' category")
  end)

  it("workshop can set a real recipe", function()
    local force = H.get_force()

    local recipe = force.recipes["iron-plate"]
    if recipe and not recipe.enabled then
      recipe.enabled = true
    end

    local workshop = H.place_workshop(35, 35)
    local set_ok = pcall(function()
      workshop.set_recipe("iron-plate")
    end)
    assert.is_true(set_ok, "set_recipe should succeed for iron-plate")

    local current_recipe = workshop.get_recipe()
    assert.are.equal("iron-plate", current_recipe and current_recipe.name or nil)
  end)
end)
