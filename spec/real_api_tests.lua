-- Real-API integration tests for Logistic Nexus.
-- These run inside a real Factorio instance via FactorioTest.
-- They exercise the actual engine: entity creation, logistic networks,
-- shortage detection, prototype data, and recipe management.

local C = require("scripts.constants")
local Storage = require("scripts.storage")
local Brain = require("scripts.brain")

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function get_surface()
  return game.surfaces[1]
end

local function get_force()
  return game.forces["player"]
end

local function place_workshop(surface, force, x, y)
  return surface.create_entity{
    name = C.WORKSHOP_NAME,
    position = {x, y},
    force = force,
    create_build_effect_smoke = false,
    raise_built = true
  }
end

local function place_roboport(surface, force, x, y)
  local roboport = surface.create_entity{
    name = "roboport",
    position = {x, y},
    force = force,
    create_build_effect_smoke = false,
    raise_built = true
  }
  if roboport and roboport.valid then
    local inv = roboport.get_inventory(defines.inventory.roboport_robot)
    if inv and inv.valid then
      inv.insert({name = "logistic-robot", count = 20})
    end
  end
  return roboport
end

local function place_supply_chest(surface, force, x, y, items)
  local chest = surface.create_entity{
    name = "passive-provider-chest",
    position = {x, y},
    force = force,
    create_build_effect_smoke = false,
    raise_built = true
  }
  if chest and chest.valid then
    local inv = chest.get_inventory(defines.inventory.chest)
    for _, item in ipairs(items) do
      inv.insert(item)
    end
  end
  return chest
end

local function place_requester(surface, force, x, y, item_name, count, quality)
  quality = quality or "normal"
  local chest = surface.create_entity{
    name = "requester-chest",
    position = {x, y},
    force = force,
    create_build_effect_smoke = false,
    raise_built = true
  }
  if chest and chest.valid then
    local point = chest.get_logistic_point(
      defines.logistic_member_index.logistic_container
    )
    if point and point.valid then
      local section = point.get_section(1)
      if section and section.valid then
        section.set_slot(1, {
          value = {
            type = "item",
            name = item_name,
            quality = quality,
            comparator = "="
          },
          min = count,
          max = count
        })
      end
    end
  end
  return chest
end

local function clean_surface()
  local surface = get_surface()
  for _, entity in pairs(surface.find_entities_filtered{force = "player"}) do
    if entity.valid and entity.name ~= "player-character" then
      pcall(function() entity.destroy() end)
    end
  end
end

------------------------------------------------------------
-- Tests
------------------------------------------------------------

describe("real API: workshop registration", function()
  before_each(function()
    clean_surface()
    Storage.init_storage()
  end)

  it("creates companion chests when a workshop is built", function()
    local surface = get_surface()
    local force = get_force()

    local workshop = place_workshop(surface, force, 10, 10)
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
    clean_surface()
    Storage.init_storage()
  end)

  it("detects a shortage and assigns a workshop to craft iron-plate", function()
    local surface = get_surface()
    local force = get_force()

    local recipe = force.recipes["iron-plate"]
    if recipe and not recipe.enabled then
      recipe.enabled = true
    end

    place_roboport(surface, force, 15, 15)
    place_supply_chest(surface, force, 20, 20, {
      {name = "iron-ore", count = 100}
    })
    place_requester(surface, force, 25, 20, "iron-plate", 10)

    local workshop = place_workshop(surface, force, 10, 10)
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
    clean_surface()
    Storage.init_storage()
  end)

  it("workshop entity has the correct crafting categories", function()
    local surface = get_surface()
    local force = get_force()
    local workshop = place_workshop(surface, force, 30, 30)

    assert.is_true(workshop.valid)
    local proto = workshop.prototype
    assert.is_not_nil(proto)
    local categories = proto.crafting_categories
    assert.is_not_nil(categories)
    assert.is_true(categories["crafting"] ~= nil, "should have 'crafting' category")
  end)

  it("workshop can set a real recipe", function()
    local surface = get_surface()
    local force = get_force()

    local recipe = force.recipes["iron-plate"]
    if recipe and not recipe.enabled then
      recipe.enabled = true
    end

    local workshop = place_workshop(surface, force, 35, 35)
    local set_ok = pcall(function()
      workshop.set_recipe("iron-plate")
    end)
    assert.is_true(set_ok, "set_recipe should succeed for iron-plate")

    local current_recipe = workshop.get_recipe()
    assert.are.equal("iron-plate", current_recipe and current_recipe.name or nil)
  end)
end)
