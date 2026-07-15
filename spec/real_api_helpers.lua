-- Shared helpers for real-API integration tests.
-- These create real Factorio entities instead of mocks.

local C = require("scripts.constants")
local Storage = require("scripts.storage")
local Brain = require("scripts.brain")
local Util = require("scripts.util")

local M = {}

------------------------------------------------------------
-- ENTITY CREATION
------------------------------------------------------------

function M.get_surface()
  return game.surfaces[1]
end

function M.get_force()
  return game.forces["player"]
end

function M.place_workshop(x, y)
  local surface = M.get_surface()
  local force = M.get_force()
  return surface.create_entity{
    name = C.WORKSHOP_NAME,
    position = {x, y},
    force = force,
    create_build_effect_smoke = false,
    raise_built = true
  }
end

function M.place_roboport(x, y)
  local surface = M.get_surface()
  local force = M.get_force()
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
      inv.insert({name = "logistic-robot", count = 50})
    end
  end
  return roboport
end

-- Provides unlimited power via electric-energy-interface.
-- Uses substations for wide area coverage.
function M.place_power(x, y)
  local surface = M.get_surface()
  local force = M.get_force()
  local eei = surface.create_entity{
    name = "electric-energy-interface",
    position = {x, y},
    force = force,
    create_build_effect_smoke = false,
    raise_built = true
  }
  if eei and eei.valid then
    eei.energy = 100000000  -- 100 MJ
  end
  -- Substation near the EEI to connect it to the grid
  surface.create_entity{
    name = "substation",
    position = {x + 3, y},
    force = force,
    create_build_effect_smoke = false,
    raise_built = true
  }
  -- Substation near the workshop area (10+ tiles away)
  surface.create_entity{
    name = "substation",
    position = {x + 9, y + 9},
    force = force,
    create_build_effect_smoke = false,
    raise_built = true
  }
  return eei
end

function M.place_supply_chest(x, y, items)
  local surface = M.get_surface()
  local force = M.get_force()
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

function M.place_requester(x, y, item_name, count, quality)
  quality = quality or "normal"
  local surface = M.get_surface()
  local force = M.get_force()
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

-- Place a constant combinator to provide circuit signals to the workshop.
function M.place_constant_combinator(x, y, signals)
  local surface = M.get_surface()
  local force = M.get_force()
  local combinator = surface.create_entity{
    name = "constant-combinator",
    position = {x, y},
    force = force,
    create_build_effect_smoke = false,
    raise_built = true
  }
  if combinator and combinator.valid then
    local behavior = combinator.get_control_behavior()
    if behavior then
      behavior.enabled = true
      local section = behavior.sections[1]
      if section then
        for i, sig in ipairs(signals) do
          section.set_slot(i, {
            value = {
              type = sig.signal.type,
              name = sig.signal.name,
              quality = "normal"
            },
            min = sig.count,
            max = sig.count
          })
        end
      end
    end
  end
  return combinator
end

-- Connect two entities with circuit wire (red).
function M.connect_circuit(entity1, entity2)
  local red1 = entity1.get_wire_connector(defines.wire_connector_id.circuit_red, true)
  local red2 = entity2.get_wire_connector(defines.wire_connector_id.circuit_red, true)
  if red1 and red2 then
    red1.connect_to(red2)
  end
end

------------------------------------------------------------
-- RECIPE / TECHNOLOGY
------------------------------------------------------------

function M.enable_recipes(names)
  local force = M.get_force()
  for _, name in ipairs(names) do
    local recipe = force.recipes[name]
    if recipe and not recipe.enabled then
      recipe.enabled = true
    end
  end
end

-- Enable all technologies up to the point where logistics and crafting are available.
function M.enable_base_tech()
  local force = M.get_force()
  -- Enable key technologies
  for _, tech_name in ipairs({
    "automation", "automation-2", "automation-3",
    "logistics", "logistics-2",
    "logistic-system"
  }) do
    local tech = force.technologies[tech_name]
    if tech and not tech.researched then
      tech.researched = true
    end
  end
end

------------------------------------------------------------
-- WORLD SETUP
------------------------------------------------------------

-- Sets up a complete test environment: power, roboport, and enables recipes.
-- Returns a table with the surface, force, and network for convenience.
function M.setup_world(opts)
  opts = opts or {}
  local surface = M.get_surface()
  local force = M.get_force()

  -- Enable base technology so recipes and logistics are available
  M.enable_base_tech()

  -- Enable specific recipes requested by the test
  if opts.recipes then
    M.enable_recipes(opts.recipes)
  end

  -- Power + roboport in the test area. Place roboport centrally so it
  -- covers workshops (~10,10) and supply chests (~20,20).
  M.place_roboport(15, 15)
  M.place_power(5, 5)

  -- Find the logistic network covering our area
  local network = surface.find_logistic_network_by_position({x = 15, y = 15}, force)

  return {
    surface = surface,
    force = force,
    network = network
  }
end

function M.clean_surface()
  local surface = M.get_surface()
  for _, entity in pairs(surface.find_entities_filtered{force = "player"}) do
    if entity.valid and entity.name ~= "player-character" then
      pcall(function() entity.destroy() end)
    end
  end
end

------------------------------------------------------------
-- DELIVERY / CRAFTING SIMULATION
------------------------------------------------------------

-- Directly insert items into a chest, simulating bot delivery.
function M.deliver_to_chest(chest, items)
  if not (chest and chest.valid) then return end
  local inv = chest.get_inventory(defines.inventory.chest)
  if inv and inv.valid then
    for _, item in ipairs(items) do
      inv.insert(item)
    end
  end
end

------------------------------------------------------------
-- STATE QUERIES
------------------------------------------------------------

function M.workshop_state(workshop_data)
  return workshop_data.assignment and workshop_data.assignment.state or "idle"
end

function M.workshop_target(workshop_data)
  return workshop_data.assignment and workshop_data.assignment.item
end

function M.workshop_requests(workshop_data)
  return workshop_data.assignment and workshop_data.assignment.requests or {}
end

function M.provider_has_item(provider, name, quality)
  if not (provider and provider.valid) then return 0 end
  local inv = provider.get_inventory(defines.inventory.chest)
  if not (inv and inv.valid) then return 0 end
  return inv.get_item_count({name = name, quality = quality or "normal"})
end

function M.requester_has_item(requester, name, quality)
  if not (requester and requester.valid) then return 0 end
  local inv = requester.get_inventory(defines.inventory.chest)
  if not (inv and inv.valid) then return 0 end
  return inv.get_item_count({name = name, quality = quality or "normal"})
end

function M.get_workshop_data(unit_number)
  return storage.workshops[unit_number]
end

-- Force the brain to reschedule on next tick.
function M.force_brain_reschedule(network)
  if not network then return end
  local key = Util.brain_key(network)
  local brain = storage.brains[key]
  if brain then
    brain.schedule_dirty = true
    brain.next_schedule_tick = 0
  end
end

------------------------------------------------------------
-- ASSERTION HELPERS
------------------------------------------------------------

-- Wait for a condition to become true, calling fn each tick.
-- Calls done() when condition is met, or times out.
function M.wait_for(timeout, condition_fn)
  async(timeout)
  on_tick(function()
    if condition_fn() then
      done()
    end
  end)
end

-- Run brain assessment + tick advancement in a loop until condition or timeout.
function M.run_until(timeout, condition_fn)
  async(timeout)
  on_tick(function()
    if game.tick % 5 == 0 then
      Brain.assess_all_workshops()
    end
    if condition_fn() then
      done()
    end
  end)
end

return M
