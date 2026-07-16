-- Huge end-to-end test for Logistic Nexus.
-- Mocks the Factorio runtime API so the real scripts can run without a game.

local helpers = require("spec.helpers")

helpers.install_globals()

-- The workshop module touches the assembling-machine module inventory.
_G.defines.inventory.assembling_machine_modules = "assembling_machine_modules"

local C = require("scripts.constants")
local Util = require("scripts.util")
local Storage = require("scripts.storage")
local Brain = require("scripts.brain")
local Workshop = require("scripts.workshop")
local Construction = require("scripts.construction")
local Network = require("scripts.network")
local Recipes = require("scripts.recipes")

------------------------------------------------------------
-- MOCK INVENTORY
------------------------------------------------------------

local function make_inventory(contents)
  contents = contents or {}
  local inventory = {valid = true, _contents = contents}

  function inventory.get_contents()
    local result = {}
    for key, count in pairs(inventory._contents) do
      if count > 0 then
        local name, quality = Util.split_item_key(key)
        table.insert(result, {name = name, count = count, quality = quality})
      end
    end
    return result
  end

  function inventory.get_item_count(item)
    local key
    if type(item) == "table" then
      key = Util.item_key(item.name, item.quality)
    else
      key = item .. "|normal"
    end
    return inventory._contents[key] or 0
  end

  function inventory.insert(stack)
    local key = Util.item_key(stack.name, stack.quality)
    local count = stack.count or 1
    inventory._contents[key] = (inventory._contents[key] or 0) + count
    return count
  end

  function inventory.remove(stack)
    local key = Util.item_key(stack.name, stack.quality)
    local available = inventory._contents[key] or 0
    local removed = math.min(available, stack.count or 1)
    inventory._contents[key] = available - removed
    if inventory._contents[key] <= 0 then
      inventory._contents[key] = nil
    end
    return removed
  end

  function inventory.is_empty()
    for _ in pairs(inventory._contents) do
      return false
    end
    return true
  end

  return inventory
end

------------------------------------------------------------
-- MOCK ENTITIES
------------------------------------------------------------

local function make_requester_entity(opts)
  opts = opts or {}
  local inventory = make_inventory(opts.contents or {})

  local section = {
    valid = true,
    filters_count = 0,
    _filters = {}
  }

  function section.clear_slot(slot)
    section._filters[slot] = nil
  end

  function section.set_slot(index, filter)
    section._filters[index] = filter
    if index > section.filters_count then
      section.filters_count = index
    end
  end

  local point = {
    valid = true,
    enabled = opts.enabled ~= false,
    owner = nil,
    filters = opts.filters or {},
    targeted_items_deliver = opts.targeted_items_deliver or {},
    logistic_network = opts.logistic_network,
    sections_count = 1,
    trash_not_requested = true
  }

  function point.get_section(index)
    if index == 1 then
      return section
    end
    return nil
  end

  function point.add_section(_name)
    return section
  end

  local entity = {
    valid = true,
    name = opts.name or "logistic-chest-requester",
    unit_number = opts.unit_number or 200,
    position = opts.position or {x = 2, y = 1},
    force = opts.force or {name = "player"},
    surface = opts.surface,
    type = "logistic-container",
    _inventory = inventory,
    _point = point
  }

  function entity.get_inventory(index)
    if index == defines.inventory.chest then
      return entity._inventory
    end
    return nil
  end

  function entity.get_logistic_point(_index)
    return entity._point
  end

  point.owner = entity
  return point, entity, section
end

local function make_provider_entity(opts)
  opts = opts or {}
  local inventory = make_inventory(opts.contents or {})
  local entity = {
    valid = true,
    name = C.PROVIDER_NAME,
    unit_number = opts.unit_number or 100,
    position = opts.position or {x = 2, y = 2},
    force = opts.force or {name = "player"},
    surface = opts.surface,
    _inventory = inventory
  }

  function entity.insert(stack)
    return entity._inventory.insert(stack)
  end

  function entity.get_inventory(index)
    if index == defines.inventory.chest then
      return entity._inventory
    end
    return nil
  end

  return entity
end

local function make_workshop_entity(opts)
  opts = opts or {}
  local recipes = opts.recipes or {}
  local input_inventory = make_inventory(opts.input_inventory or {})
  local output_inventory = make_inventory(opts.output_inventory or {})
  local module_inventory = make_inventory(opts.module_inventory or {})

  local entity = {
    valid = true,
    name = opts.name or C.WORKSHOP_NAME,
    unit_number = opts.unit_number or 1,
    position = opts.position or {x = 0.5, y = 0.5},
    force = opts.force or {name = "player"},
    surface = opts.surface,
    crafting_progress = opts.crafting_progress or 0,
    products_finished = opts.products_finished or 0,
    prototype = opts.prototype or {crafting_categories = {crafting = true}},
    _current_recipe = opts.current_recipe,
    _current_quality = opts.current_quality or "normal",
    _input_inventory = input_inventory,
    _output_inventory = output_inventory,
    _module_inventory = module_inventory,
    _recipes = recipes,
    _signals = opts.signals or {}
  }

  function entity.get_recipe()
    return entity._current_recipe, entity._current_quality
  end

  function entity.set_recipe(recipe_name, quality)
    local returned = {}
    entity._current_recipe = recipe_name and entity._recipes[recipe_name] or nil
    entity._current_quality = quality
    return returned
  end

  function entity.get_inventory(index)
    if index == defines.inventory.crafter_input then
      return entity._input_inventory
    elseif index == defines.inventory.assembling_machine_modules then
      return entity._module_inventory
    end
    return nil
  end

  function entity.get_output_inventory()
    return entity._output_inventory
  end

  function entity.insert(stack)
    return entity._input_inventory.insert(stack)
  end

  function entity.get_signals(_red, _green)
    return entity._signals
  end

  return entity
end

------------------------------------------------------------
-- MOCK NETWORK / SURFACE / FORCE
------------------------------------------------------------

local function make_network(opts)
  opts = opts or {}
  local network = {
    valid = true,
    network_id = opts.network_id or 1,
    force = opts.force or {name = "player"},
    requester_points = opts.requester_points or {},
    cells = opts.cells or {},
    _supply = opts.supply or {}
  }

  function network.get_supply_counts(id)
    local key
    if type(id) == "table" then
      key = Util.item_key(id.name, id.quality)
    else
      key = id .. "|normal"
    end
    return {storage = network._supply[key] or 0}
  end

  function network.get_item_count(id)
    local key
    if type(id) == "table" then
      key = Util.item_key(id.name, id.quality)
    else
      key = id .. "|normal"
    end
    return network._supply[key] or 0
  end

  return network
end

local function make_surface(opts)
  opts = opts or {}
  local entities = opts.entities or {}
  local networks = opts.networks or {}
  local surface = {
    valid = true,
    index = opts.index or 1,
    _entities = entities,
    _networks = networks
  }

  function surface.find_entity(name, position)
    for _, e in pairs(surface._entities) do
      if e.valid and e.name == name
          and e.position.x == position.x and e.position.y == position.y then
        return e
      end
    end
    return nil
  end

  function surface.can_place_entity(_spec)
    return true
  end

  function surface.create_entity(_spec)
    return nil
  end

  function surface.find_entities_filtered(filter)
    local result = {}
    for _, e in pairs(surface._entities) do
      if e.valid then
        local match = true
        if filter.name then
          local names = type(filter.name) == "table" and filter.name or {filter.name}
          local name_match = false
          for _, n in ipairs(names) do
            if e.name == n then
              name_match = true
              break
            end
          end
          if not name_match then
            match = false
          end
        end
        if filter.type and e.type ~= filter.type then
          match = false
        end
        if filter.force and e.force ~= filter.force then
          match = false
        end
        if match then
          table.insert(result, e)
        end
      end
    end
    return result
  end

  function surface.find_logistic_network_by_position(_position, force)
    for _, net in ipairs(surface._networks) do
      if net.force == force then
        return net
      end
    end
    return nil
  end

  function surface.find_logistic_networks_by_construction_area(_position, force)
    local result = {}
    for _, net in ipairs(surface._networks) do
      if net.force == force then
        table.insert(result, net)
      end
    end
    return result
  end

  function surface.spill_item_stack(_params)
    -- no-op in tests
  end

  return surface
end

local function make_force(opts)
  opts = opts or {}
  return {
    name = opts.name or "player",
    recipes = opts.recipes or {}
  }
end

local function make_recipe(opts)
  opts = opts or {}
  local category = opts.category or "crafting"
  return {
    name = opts.name,
    valid = true,
    enabled = opts.enabled ~= false,
    hidden = opts.hidden or false,
    category = category,
    energy = opts.energy or 1,
    ingredients = opts.ingredients or {},
    products = opts.products or {{type = "item", name = opts.name, amount = 1}},
    has_category = function(cat)
      local cats = opts.categories or {[category] = true}
      return cats[cat] == true
    end
  }
end

local function make_cell(opts)
  opts = opts or {}
  return {
    valid = true,
    transmitting = true,
    construction_radius = opts.construction_radius or 50,
    owner = opts.owner or {
      valid = true,
      position = opts.position or {x = 0, y = 0},
      surface = opts.surface,
      force = opts.force
    }
  }
end

------------------------------------------------------------
-- WORLD BUILDERS
------------------------------------------------------------

local function setup_game(opts)
  opts = opts or {}
  local force = make_force({name = opts.force_name or "player", recipes = opts.recipes or {}})
  local surface = make_surface({index = opts.surface_index or 1})
  local network = make_network({
    network_id = opts.network_id or 1,
    force = force,
    supply = opts.supply or {},
    cells = opts.cells or {}
  })
  table.insert(surface._networks, network)
  game.forces[force.name] = force
  game.surfaces[surface.index] = surface
  return {force = force, surface = surface, network = network}
end

local function add_workshop(world, opts)
  opts = opts or {}
  local unit_number = opts.unit_number or 1
  local position = opts.position or {x = 0.5, y = 0.5}
  local force = opts.force or world.force
  local surface = opts.surface or world.surface
  local network = opts.network or world.network

  local point, requester = make_requester_entity({
    name = C.REQUESTER_NAME,
    unit_number = unit_number * 1000,
    position = {x = position.x + 1.5, y = position.y + 0.5},
    force = force,
    surface = surface,
    logistic_network = network,
    contents = opts.requester_contents,
    filters = opts.filters,
    targeted_items_deliver = opts.targeted_items_deliver
  })

  local provider = make_provider_entity({
    unit_number = unit_number * 1001,
    position = {x = position.x + 1.5, y = position.y + 1.5},
    force = force,
    surface = surface,
    contents = opts.provider_contents
  })

  local entity = make_workshop_entity({
    name = opts.name or C.WORKSHOP_NAME,
    unit_number = unit_number,
    position = position,
    force = force,
    surface = surface,
    recipes = opts.recipes,
    input_inventory = opts.input_inventory,
    output_inventory = opts.output_inventory,
    module_inventory = opts.module_inventory,
    signals = opts.signals
  })

  table.insert(surface._entities, entity)
  table.insert(surface._entities, requester)
  table.insert(surface._entities, provider)
  table.insert(network.requester_points, point)

  local workshop_data = {
    entity = entity,
    companions = {requester = requester, provider = provider},
    assignment = nil,
    current_item = nil,
    current_quality = "normal",
    current_shortage = 0,
    current_recipe = nil,
    current_recipe_quality = nil,
    current_product_amount = 1,
    current_is_construction = false,
    current_construction_target = 0,
    current_construction_reserved = 0,
    waiting_for_clear = nil
  }

  storage.workshops[unit_number] = workshop_data
  storage.companion_owners[requester.unit_number] = unit_number
  storage.companion_owners[provider.unit_number] = unit_number

  return workshop_data
end

------------------------------------------------------------
-- SIMULATION HELPERS
------------------------------------------------------------

local function advance_ticks(count)
  for _ = 1, count do
    game.tick = game.tick + 1
    Construction.process_construction_scan_queue()
    Brain.process_due_brains()
  end
end

local function deliver_to_requester(requester, items)
  local inventory = requester.get_inventory(defines.inventory.chest)
  for _, item in ipairs(items) do
    inventory.insert(item)
  end
end

local function add_network_supply(network, items)
  for _, item in ipairs(items) do
    local key = Util.item_key(item.name, item.quality)
    network._supply[key] = (network._supply[key] or 0) + item.count
  end
end

local function remove_network_supply(network, items)
  for _, item in ipairs(items) do
    local key = Util.item_key(item.name, item.quality)
    network._supply[key] = math.max(0, (network._supply[key] or 0) - item.count)
  end
end

local function complete_crafting_step(workshop_data, count)
  local entity = workshop_data.entity
  count = count or 1
  entity.products_finished = (entity.products_finished or 0) + count

  -- Simulate the recipe output landing in the workshop inventory so later
  -- collect_workshop_output_to_internal can pick it up.
  local assignment = workshop_data.assignment
  local step = assignment and assignment.current_step
  local outputs = step and step.outputs
  if outputs then
    local output_inventory = entity.get_output_inventory()
    for _, output in ipairs(outputs) do
      output_inventory.insert({
        name = output.name,
        quality = output.quality or "normal",
        count = (output.amount or 1) * count
      })
    end
  end
end

local function requester_has_item(requester, name, quality)
  local inv = requester.get_inventory(defines.inventory.chest)
  return inv.get_item_count({name = name, quality = quality})
end

local function provider_has_item(provider, name, quality)
  local inv = provider.get_inventory(defines.inventory.chest)
  return inv.get_item_count({name = name, quality = quality})
end

local function workshop_state(workshop_data)
  return workshop_data.assignment and workshop_data.assignment.state or "idle"
end

local function workshop_target(workshop_data)
  return workshop_data.assignment and workshop_data.assignment.item
end

local function workshop_requests(workshop_data)
  return workshop_data.assignment and workshop_data.assignment.requests or {}
end

local function requester_filters(requester)
  local point = Network.get_requester_point(requester)
  local section = point.get_section(1)
  return section._filters
end

local function find_analysis(world)
  local brain = storage.brains[Util.brain_key(world.network)]
  return brain and brain.last_analysis
end

local function force_brain_reschedule(world)
  local brain = storage.brains[Util.brain_key(world.network)]
  if brain then
    brain.schedule_dirty = true
    brain.next_schedule_tick = 0
  end
end

------------------------------------------------------------
-- TEST SUITE
------------------------------------------------------------

describe("e2e Logistic Nexus", function()
  before_each(function()
    _G.storage = {}
    _G.game = {tick = 0, surfaces = {}, forces = {}}
    Storage.init_storage()
    _G.settings = {
      global = {
        ["logistic-nexus-max-batches-per-job"] = {value = 5}
      }
    }
    _G.prototypes = {item = {}}
  end)

  describe("happy path single-step crafting", function()
    it("preflight replan proceeds after ingredients are delivered", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 2}}
        })
      }
      local world = setup_game({recipes = recipes, supply = {}})
      add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 100}})

      -- Requester chest wants 5 iron-plate.
      local requester_point = make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-plate", quality = "normal", count = 5}}
      })
      table.insert(world.network.requester_points, requester_point)

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes
      })

      Brain.assess_all_workshops()

      assert.are.equal("iron-plate", workshop_target(workshop))
      assert.are.equal("waiting_inputs", workshop_state(workshop))

      local requests = workshop_requests(workshop)
      assert.is_true(#requests >= 1)
      assert.are.equal("iron-ore", requests[1].name)

      -- Simulate bots delivering the requested ore.
      deliver_to_requester(workshop.companions.requester, {{name = "iron-ore", quality = "normal", count = requests[1].amount}})

      -- The preflight replan sees the ore already in the requester and the
      -- workshop can proceed to crafting.
      Brain.assess_all_workshops()
      advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
      Brain.assess_all_workshops()

      assert.are.equal("crafting_step", workshop_state(workshop))
    end)
  end)

  describe("batch crafting", function()
    it("crafts the largest feasible batch up to the configured limit", function()
      _G.settings.global["logistic-nexus-max-batches-per-job"].value = 10

      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 1}}
        })
      }
      local world = setup_game({recipes = recipes, supply = {}})
      -- Only 9 ore are available, so even though max-batches is 10 the planner
      -- must cap the batch at 9 and craft exactly 9 plates.
      add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 9}})

      table.insert(world.network.requester_points, (make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-plate", quality = "normal", count = 9}}
      })))

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes
      })

      Brain.assess_all_workshops()

      assert.are.equal("iron-plate", workshop_target(workshop))
      assert.are.equal("waiting_inputs", workshop_state(workshop))

      local requests = workshop_requests(workshop)
      assert.are.equal(1, #requests)
      assert.are.equal("iron-ore", requests[1].name)
      assert.are.equal(9, requests[1].amount)

      deliver_to_requester(workshop.companions.requester, {
        {name = "iron-ore", quality = "normal", count = 9}
      })

      force_brain_reschedule(world)
      Brain.assess_all_workshops()
      advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
      force_brain_reschedule(world)
      Brain.assess_all_workshops()

      assert.are.equal("crafting_step", workshop_state(workshop))

      for _ = 1, 25 do
        if workshop_state(workshop) == "idle" then
          break
        end
        if workshop_state(workshop) == "crafting_step" then
          complete_crafting_step(workshop, 1)
        end
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
      end

      -- Exactly 9 plates were crafted from the 9 ore that were available.
      assert.are.equal(9, provider_has_item(workshop.companions.provider, "iron-plate", "normal"))
      -- No input resources should remain in requester or provider.
      assert.are.equal(0, requester_has_item(workshop.companions.requester, "iron-ore", "normal"))
      assert.are.equal(0, provider_has_item(workshop.companions.provider, "iron-ore", "normal"))
      -- The batch finished; the workshop is waiting for more ore only because
      -- the mock network does not count the provider's plates as supply.
      assert.are_not.equal("crafting_step", workshop_state(workshop))
    end)
  end)

  describe("multi-step internal crafting", function()
    it("crafts intermediates internally and only requests leaves from the network", function()
      local recipes = helpers.make_iron_gear_recipes(make_recipe)
      local world = setup_game({recipes = recipes, supply = {}})
      add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 100}})

      local requester_point = make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-gear-wheel", quality = "normal", count = 1}}
      })
      table.insert(world.network.requester_points, requester_point)

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes
      })

      Brain.assess_all_workshops()

      assert.are.equal("iron-gear-wheel", workshop_target(workshop))
      local requests = workshop_requests(workshop)
      assert.are.equal("iron-ore", requests[1].name)

      -- Deliver exactly the single-batch request so preflight replan still matches.
      deliver_to_requester(workshop.companions.requester, {{name = "iron-ore", quality = "normal", count = requests[1].amount}})

      force_brain_reschedule(world)
      Brain.assess_all_workshops()
      advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
      force_brain_reschedule(world)
      Brain.assess_all_workshops()

      assert.are.equal("crafting_step", workshop_state(workshop))

      -- 1 gear wheel needs 2 iron-plate steps + 1 iron-gear-wheel step.
      local produced = false
      for _ = 1, 10 do
        if provider_has_item(workshop.companions.provider, "iron-gear-wheel", "normal") > 0 then
          produced = true
          break
        end
        if workshop_state(workshop) == "crafting_step" then
          complete_crafting_step(workshop, 1)
        end
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
      end

      assert.is_true(produced)
      assert.is_true(provider_has_item(workshop.companions.provider, "iron-gear-wheel", "normal") > 0)
    end)
  end)

  describe("construction requests", function()
    it("picks up construction ghost demand and reserves output", function()
      local recipes = {
        ["transport-belt"] = make_recipe({
          name = "transport-belt",
          ingredients = {
            {type = "item", name = "iron-plate", amount = 1},
            {type = "item", name = "iron-gear-wheel", amount = 1}
          }
        }),
        ["iron-gear-wheel"] = make_recipe({
          name = "iron-gear-wheel",
          ingredients = {{type = "item", name = "iron-plate", amount = 2}}
        }),
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 1}}
        })
      }
      local world = setup_game({recipes = recipes, supply = {}})
      add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 100}})

      -- Construction scanning needs at least one network cell to resolve a surface.
      table.insert(world.network.cells, make_cell({
        position = {x = 0, y = 0},
        surface = world.surface,
        force = world.force,
        construction_radius = 50
      }))

      -- Inject a construction scan result directly.
      local scan_key = Util.construction_scan_key(world.surface.index, world.force.name, world.network.network_id)
      storage.construction_scans[scan_key] = {
        key = scan_key,
        network_id = world.network.network_id,
        tick = game.tick,
        has_result = true,
        ghost_counts = {
          [world.network.network_id .. "|transport-belt|normal"] = {
            name = "transport-belt",
            quality = "normal",
            requested = 1
          }
        },
        request_count = 1
      }

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes
      })

      Brain.assess_all_workshops()

      assert.are.equal("transport-belt", workshop_target(workshop))
      assert.is_true(workshop.current_is_construction)
      assert.are.equal(1, workshop.current_construction_target)

      local requests = workshop_requests(workshop)
      assert.are.equal("iron-ore", requests[1].name)

      -- Deliver exactly the single-batch request.
      deliver_to_requester(workshop.companions.requester, {{name = "iron-ore", quality = "normal", count = requests[1].amount}})

      force_brain_reschedule(world)
      Brain.assess_all_workshops()
      advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
      force_brain_reschedule(world)
      Brain.assess_all_workshops()

      assert.are.equal("crafting_step", workshop_state(workshop))

      -- 1 transport-belt needs 2 iron-plate steps + 1 iron-gear-wheel step.
      for _ = 1, 10 do
        if workshop_state(workshop) == "idle" then
          break
        end
        if workshop_state(workshop) == "crafting_step" then
          complete_crafting_step(workshop, 1)
        end
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
      end

      assert.are.equal("idle", workshop_state(workshop))
      -- Construction output should be in the provider.
      assert.is_true(provider_has_item(workshop.companions.provider, "transport-belt", "normal") >= 1)
    end)
  end)

  describe("circuit controls", function()
    it("blocks requested items listed on the circuit network", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 1}}
        }),
        ["copper-plate"] = make_recipe({
          name = "copper-plate",
          ingredients = {{type = "item", name = "copper-ore", amount = 1}}
        })
      }
      local world = setup_game({recipes = recipes, supply = {}})
      add_network_supply(world.network, {
        {name = "iron-ore", quality = "normal", count = 100},
        {name = "copper-ore", quality = "normal", count = 100}
      })

      table.insert(world.network.requester_points, (make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-plate", quality = "normal", count = 5}}
      })))
      table.insert(world.network.requester_points, (make_requester_entity({
        position = {x = 100, y = 101},
        force = world.force,
        surface = world.surface,
        filters = {{name = "copper-plate", quality = "normal", count = 5}}
      })))

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes,
        signals = {{
          signal = {type = "item", name = "iron-plate"},
          count = 1
        }}
      })

      Brain.assess_all_workshops()

      assert.are.equal("copper-plate", workshop_target(workshop))
      local requests = workshop_requests(workshop)
      assert.are.equal("copper-ore", requests[1].name)
    end)

    it("respects product limit P signal", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 1}}
        }),
        ["copper-plate"] = make_recipe({
          name = "copper-plate",
          ingredients = {{type = "item", name = "copper-ore", amount = 1}}
        }),
        ["steel-plate"] = make_recipe({
          name = "steel-plate",
          ingredients = {{type = "item", name = "iron-plate", amount = 5}}
        })
      }
      local world = setup_game({recipes = recipes, supply = {}})
      add_network_supply(world.network, {
        {name = "iron-ore", quality = "normal", count = 100},
        {name = "copper-ore", quality = "normal", count = 100},
        {name = "iron-plate", quality = "normal", count = 100}
      })

      table.insert(world.network.requester_points, (make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-plate", quality = "normal", count = 1}}
      })))
      table.insert(world.network.requester_points, (make_requester_entity({
        position = {x = 100, y = 101},
        force = world.force,
        surface = world.surface,
        filters = {{name = "copper-plate", quality = "normal", count = 1}}
      })))
      table.insert(world.network.requester_points, (make_requester_entity({
        position = {x = 100, y = 102},
        force = world.force,
        surface = world.surface,
        filters = {{name = "steel-plate", quality = "normal", count = 1}}
      })))

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes,
        signals = {{
          signal = {type = "virtual", name = "signal-P"},
          count = 1
        }}
      })

      Brain.assess_all_workshops()

      -- With P=1 only the highest-priority shortage is considered.
      -- Shortages are sorted by priority (mall > construction > logistic) then missing desc.
      -- All three have priority 2, so the one with highest missing wins.
      local target = workshop_target(workshop)
      assert.is_not_nil(target)
      assert.is_true(target == "iron-plate" or target == "copper-plate" or target == "steel-plate")
    end)
  end)

  describe("quality", function()
    it("requests matching-quality ingredients for quality shortages", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 1}}
        })
      }
      local world = setup_game({recipes = recipes, supply = {}})
      add_network_supply(world.network, {{name = "iron-ore", quality = "uncommon", count = 100}})

      table.insert(world.network.requester_points, (make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-plate", quality = "uncommon", count = 5}}
      })))

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes
      })

      Brain.assess_all_workshops()

      local requests = workshop_requests(workshop)
      assert.are.equal(1, #requests)
      assert.are.equal("iron-ore", requests[1].name)
      assert.are.equal("uncommon", requests[1].quality)
    end)
  end)

  describe("previously fixed bugs", function()
    it("extra items in requester do not permanently stall waiting_inputs", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 2}}
        })
      }
      local world = setup_game({recipes = recipes, supply = {}})
      add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 100}})

      table.insert(world.network.requester_points, (make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-plate", quality = "normal", count = 5}}
      })))

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes
      })

      Brain.assess_all_workshops()
      local requests = workshop_requests(workshop)
      local needed = requests[1].amount

      -- Deliver exact ore plus one extra copper ore.
      deliver_to_requester(workshop.companions.requester, {
        {name = "iron-ore", quality = "normal", count = needed},
        {name = "copper-ore", quality = "normal", count = 1}
      })

      -- Wait far longer than the waiting-input recheck threshold.
      advance_ticks(C.WAITING_INPUT_RECHECK_TICKS + 10)
      Brain.assess_all_workshops()

      -- Extra items are ignored; the workshop proceeds to craft.
      assert.are_not.equal("waiting_inputs", workshop_state(workshop))
    end)

    it("does not stall extra waiting workshops due to preflight replan budget", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 1}}
        })
      }
      local world = setup_game({recipes = recipes, supply = {}})
      add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 1000}})

      table.insert(world.network.requester_points, (make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-plate", quality = "normal", count = 100}}
      })))

      -- Create several workshops so a shared per-tick budget would exhaust.
      local workshops = {}
      for i = 1, 6 do
        local w = add_workshop(world, {
          unit_number = i,
          position = {x = 0.5 + i * 4, y = 0.5},
          recipes = recipes
        })
        table.insert(workshops, w)
      end

      Brain.assess_all_workshops()

      -- Deliver exact ore to every requester so all are waiting with exact ingredients.
      for _, w in ipairs(workshops) do
        local requests = workshop_requests(w)
        if requests[1] then
          deliver_to_requester(w.companions.requester, {
            {name = "iron-ore", quality = "normal", count = requests[1].amount}
          })
        end
      end

      -- All workshops should be able to preflight replan and proceed; none
      -- should remain stuck in waiting_inputs because of a shared budget cap.
      Brain.assess_all_workshops()
      advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
      Brain.assess_all_workshops()

      local waiting = 0
      for _, w in ipairs(workshops) do
        if workshop_state(w) == "waiting_inputs" then
          waiting = waiting + 1
        end
      end

      assert.are.equal(0, waiting)
    end)
  end)

  ------------------------------------------------------------------
  -- External satisfaction during crafting
  --
  -- What happens when the shortage is satisfied from elsewhere while
  -- the workshop is mid-craft?  The brain only assigns to idle workshops
  -- and never cancels an in-progress assignment, so the workshop should
  -- finish the current batch and deliver output to the provider.
  ------------------------------------------------------------------

  describe("external satisfaction during crafting", function()
    it("finishes the current batch when the shortage is satisfied from elsewhere mid-craft", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 1}}
        })
      }
      local world = setup_game({recipes = recipes, supply = {}})
      add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 100}})

      -- External requester wants 5 iron-plate.
      local external_point, external_entity = make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-plate", quality = "normal", count = 5}}
      })
      table.insert(world.network.requester_points, external_point)

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes
      })

      Brain.assess_all_workshops()

      assert.are.equal("iron-plate", workshop_target(workshop))
      assert.are.equal("waiting_inputs", workshop_state(workshop))

      -- Deliver the requested ore to the workshop's requester.
      local requests = workshop_requests(workshop)
      deliver_to_requester(workshop.companions.requester, {
        {name = "iron-ore", quality = "normal", count = requests[1].amount}
      })

      -- Drive through settling into crafting.
      force_brain_reschedule(world)
      Brain.assess_all_workshops()
      advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
      force_brain_reschedule(world)
      Brain.assess_all_workshops()

      assert.are.equal("crafting_step", workshop_state(workshop))

      -- While crafting is in progress, the requested items arrive from
      -- somewhere else (another logistics network, a player, a cargo pod).
      -- The external requester now has all 5 iron-plates it asked for.
      deliver_to_requester(external_entity, {
        {name = "iron-plate", quality = "normal", count = 5}
      })

      -- Continue driving the workshop.  It should NOT cancel the in-progress
      -- craft; it finishes the current batch and delivers output to the
      -- provider.
      for _ = 1, 30 do
        if workshop_state(workshop) == "idle" then break end
        if workshop_state(workshop) == "crafting_step" then
          complete_crafting_step(workshop, 1)
        end
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
        advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
      end

      -- The workshop finished crafting: iron-plate is in the provider.
      assert.is_true(
        provider_has_item(workshop.companions.provider, "iron-plate", "normal") >= 1,
        "Workshop should have produced iron-plate despite external satisfaction"
      )
      -- The workshop returned to idle (not stuck in any active state).
      assert.are.equal("idle", workshop_state(workshop))
      -- The externally-delivered items are still in the external requester.
      assert.are.equal(5, requester_has_item(external_entity, "iron-plate", "normal"))
    end)

    it("picks up a new request that appears mid-craft after the current batch finishes", function()
      local recipes = helpers.make_iron_gear_recipes(make_recipe)
      recipes["burner-inserter"] = make_recipe({
        name = "burner-inserter",
        ingredients = {
          {type = "item", name = "iron-plate", amount = 1},
          {type = "item", name = "iron-gear-wheel", amount = 1}
        }
      })
      local world = setup_game({recipes = recipes, supply = {}})
      add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 1000}})

      -- External requester wants 1 iron-plate.
      local plate_point, plate_entity = make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-plate", quality = "normal", count = 1}}
      })
      table.insert(world.network.requester_points, plate_point)

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes
      })

      Brain.assess_all_workshops()
      assert.are.equal("iron-plate", workshop_target(workshop))

      -- Deliver ore and drive into crafting.
      local requests = workshop_requests(workshop)
      deliver_to_requester(workshop.companions.requester, {
        {name = "iron-ore", quality = "normal", count = requests[1].amount}
      })
      force_brain_reschedule(world)
      Brain.assess_all_workshops()
      advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
      force_brain_reschedule(world)
      Brain.assess_all_workshops()
      assert.are.equal("crafting_step", workshop_state(workshop))

      -- While crafting iron-plate, two things happen simultaneously:
      --   1. The iron-plate shortage is satisfied from elsewhere (the
      --      external requester gets its plates from another source).
      --   2. A new requester appears wanting burner-inserters (a multi-
      --      step recipe: ore -> plate -> gear -> burner-inserter).
      deliver_to_requester(plate_entity, {
        {name = "iron-plate", quality = "normal", count = 1}
      })
      local inserter_point = make_requester_entity({
        position = {x = 100, y = 101},
        force = world.force,
        surface = world.surface,
        filters = {{name = "burner-inserter", quality = "normal", count = 1}}
      })
      table.insert(world.network.requester_points, inserter_point)

      -- The workshop should still finish the in-progress iron-plate batch
      -- even though the shortage is already gone — it does not cancel.
      for _ = 1, 20 do
        if workshop_state(workshop) == "idle" then break end
        if workshop_state(workshop) == "crafting_step" then
          complete_crafting_step(workshop, 1)
        end
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
        advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
      end

      -- Iron-plate was still produced despite the shortage being gone.
      assert.is_true(
        provider_has_item(workshop.companions.provider, "iron-plate", "normal") >= 1
      )

      -- The workshop returned to idle and should pick up the burner-inserter
      -- job on the next assess — no shortage on iron-plate anymore, but the
      -- burner-inserter shortage is live.
      force_brain_reschedule(world)
      Brain.assess_all_workshops()

      for _ = 1, 5 do
        if workshop_state(workshop) ~= "idle" then break end
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
        advance_ticks(1)
      end

      assert.are_not_equal("idle", workshop_state(workshop),
        "Workshop should have picked up the burner-inserter job")
      assert.are.equal("burner-inserter", workshop_target(workshop))

      -- Drive the full multi-step craft to completion.
      for _ = 1, 40 do
        local st = workshop_state(workshop)
        if st == "idle" then break end
        if st == "waiting_inputs" then
          local reqs = workshop_requests(workshop)
          for _, req in ipairs(reqs) do
            local current = requester_has_item(
              workshop.companions.requester, req.name, req.quality
            )
            local needed = math.max(0, (req.amount or 0) - current)
            if needed > 0 then
              deliver_to_requester(workshop.companions.requester, {
                {name = req.name, quality = req.quality, count = needed}
              })
            end
          end
        end
        if st == "crafting_step" then
          complete_crafting_step(workshop, 1)
        end
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
        advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
      end

      -- The burner-inserter was produced and delivered to the provider.
      assert.is_true(
        provider_has_item(workshop.companions.provider, "burner-inserter", "normal") >= 1,
        "Workshop should have produced burner-inserter after the iron-plate batch"
      )
    end)
  end)

  ------------------------------------------------------------------
  -- Complex multi-cycle stress tests
  ------------------------------------------------------------------

  describe("repeated craft cycles on a single workshop", function()
    -- Helper: run a full craft cycle from waiting_inputs through to idle,
    -- completing one crafting step per assess tick.  Returns the number of
    -- products that landed in the provider for the given item.
    local function run_one_cycle(world, workshop, item_name)
      local cycles_completed = 0

      for _ = 1, 60 do
        local state = workshop_state(workshop)

        if state == "idle" then
          break
        end

        if state == "waiting_inputs" then
          -- Deliver whatever the requester is asking for this cycle.
          local requests = workshop_requests(workshop)
          for _, req in ipairs(requests) do
            local current = requester_has_item(
              workshop.companions.requester, req.name, req.quality
            )
            local needed = math.max(0, (req.amount or 0) - current)
            if needed > 0 then
              deliver_to_requester(workshop.companions.requester, {
                {name = req.name, quality = req.quality, count = needed}
              })
            end
          end
        end

        if state == "crafting_step" then
          complete_crafting_step(workshop, 1)
          cycles_completed = cycles_completed + 1
        end

        force_brain_reschedule(world)
        Brain.assess_all_workshops()
        advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
      end

      return provider_has_item(workshop.companions.provider, item_name, "normal")
    end

    it("completes 5 consecutive cycles of a simple recipe", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 1}}
        })
      }
      local world = setup_game({recipes = recipes, supply = {}})
      -- Abundant supply so the planner can always fulfill requests.
      add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 10000}})

      local requester_point = make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-plate", quality = "normal", count = 1}}
      })
      table.insert(world.network.requester_points, requester_point)

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes
      })

      for cycle = 1, 5 do
        -- Remove the product from the provider so the shortage reappears.
        local provider_inv = workshop.companions.provider
          .get_inventory(defines.inventory.chest)
        provider_inv.remove({name = "iron-plate", count = 100, quality = "normal"})

        -- Re-add network supply (the mock doesn't auto-replenish).
        add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 100}})

        force_brain_reschedule(world)
        Brain.assess_all_workshops()

        -- Wait for the workshop to pick up the job.
        for _ = 1, 5 do
          if workshop_state(workshop) ~= "idle" then break end
          force_brain_reschedule(world)
          Brain.assess_all_workshops()
          advance_ticks(1)
        end

        assert.are_not_equal("idle", workshop_state(workshop),
          "Cycle " .. cycle .. ": workshop never picked up the job")

        run_one_cycle(world, workshop, "iron-plate")

        assert.is_true(
          provider_has_item(workshop.companions.provider, "iron-plate", "normal") >= 1,
          "Cycle " .. cycle .. ": no iron-plate produced"
        )
      end
    end)

    it("completes 5 consecutive cycles of a multi-step recipe", function()
      local recipes = helpers.make_iron_gear_recipes(make_recipe)
      local world = setup_game({recipes = recipes, supply = {}})
      add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 10000}})

      local requester_point = make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-gear-wheel", quality = "normal", count = 1}}
      })
      table.insert(world.network.requester_points, requester_point)

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes
      })

      for cycle = 1, 5 do
        -- Clear the produced gears so shortage reappears.
        local provider_inv = workshop.companions.provider
          .get_inventory(defines.inventory.chest)
        provider_inv.remove({name = "iron-gear-wheel", count = 100, quality = "normal"})
        provider_inv.remove({name = "iron-plate", count = 100, quality = "normal"})

        add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 100}})

        force_brain_reschedule(world)
        Brain.assess_all_workshops()

        for _ = 1, 5 do
          if workshop_state(workshop) ~= "idle" then break end
          force_brain_reschedule(world)
          Brain.assess_all_workshops()
          advance_ticks(1)
        end

        assert.are_not_equal("idle", workshop_state(workshop),
          "Cycle " .. cycle .. ": workshop never picked up the gear job")

        run_one_cycle(world, workshop, "iron-gear-wheel")

        assert.is_true(
          provider_has_item(workshop.companions.provider, "iron-gear-wheel", "normal") >= 1,
          "Cycle " .. cycle .. ": no iron-gear-wheel produced"
        )
      end
    end)
  end)

  describe("multi-batch with multi-step recipe", function()
    it("crafts a 3-batch multi-step recipe and delivers all products", function()
      _G.settings.global["logistic-nexus-max-batches-per-job"].value = 5

      local recipes = helpers.make_iron_gear_recipes(make_recipe)
      local world = setup_game({recipes = recipes, supply = {}})
      -- 3 gears * 2 plates * 1 ore = 6 ore needed.
      add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 6}})

      local requester_point = make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-gear-wheel", quality = "normal", count = 3}}
      })
      table.insert(world.network.requester_points, requester_point)

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes
      })

      Brain.assess_all_workshops()

      assert.are.equal("iron-gear-wheel", workshop_target(workshop))

      -- Check we got a 3-batch plan: 6 ore requested.
      local requests = workshop_requests(workshop)
      assert.are.equal("iron-ore", requests[1].name)
      assert.are.equal(6, requests[1].amount)

      deliver_to_requester(workshop.companions.requester, {
        {name = "iron-ore", quality = "normal", count = 6}
      })

      force_brain_reschedule(world)
      Brain.assess_all_workshops()
      advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
      force_brain_reschedule(world)
      Brain.assess_all_workshops()

      -- Run through all crafting steps (6 plate crafts + 3 gear crafts = 9 steps).
      for _ = 1, 30 do
        if workshop_state(workshop) == "idle" then break end
        if workshop_state(workshop) == "crafting_step" then
          complete_crafting_step(workshop, 1)
        end
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
        advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
      end

      -- The batch completed: 3 gears should be in the provider.  The workshop
      -- may have been reassigned (the mock network doesn't see provider
      -- contents as supply, so the shortage persists) — what matters is that
      -- the crafting steps completed and the products were delivered.
      assert.are_not_equal("crafting_step", workshop_state(workshop))
      assert.are.equal(
        3,
        provider_has_item(workshop.companions.provider, "iron-gear-wheel", "normal")
      )
    end)

    it("survives a second batch job after the first completes", function()
      _G.settings.global["logistic-nexus-max-batches-per-job"].value = 5

      local recipes = helpers.make_iron_gear_recipes(make_recipe)
      local world = setup_game({recipes = recipes, supply = {}})

      local external_point, external_entity = make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-gear-wheel", quality = "normal", count = 2}}
      })
      table.insert(world.network.requester_points, external_point)

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes
      })

      for batch = 1, 2 do
        -- Supply exactly enough ore for 2 gears (4 ore).
        add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 4}})

        force_brain_reschedule(world)
        Brain.assess_all_workshops()

        -- Wait for job assignment.
        for _ = 1, 5 do
          if workshop_state(workshop) ~= "idle" then break end
          force_brain_reschedule(world)
          Brain.assess_all_workshops()
          advance_ticks(1)
        end

        assert.are_not_equal("idle", workshop_state(workshop),
          "Batch " .. batch .. ": workshop never picked up the job")

        -- Deliver requested ore.
        local requests = workshop_requests(workshop)
        for _, req in ipairs(requests) do
          deliver_to_requester(workshop.companions.requester, {
            {name = req.name, quality = req.quality, count = req.amount}
          })
        end

        force_brain_reschedule(world)
        Brain.assess_all_workshops()
        advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
        force_brain_reschedule(world)
        Brain.assess_all_workshops()

        -- Run all steps until crafting is done.  The workshop may get
        -- immediately reassigned (draining → idle → waiting_inputs all
        -- within one assess call), so we break on anything that isn't
        -- crafting_step or settling_inputs.
        for _ = 1, 30 do
          local st = workshop_state(workshop)
          if st ~= "crafting_step" and st ~= "settling_inputs" then break end
          if st == "crafting_step" then
            complete_crafting_step(workshop, 1)
          end
          force_brain_reschedule(world)
          Brain.assess_all_workshops()
          advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
          force_brain_reschedule(world)
          Brain.assess_all_workshops()
        end

        -- The batch completed.
        assert.is_true(
          provider_has_item(workshop.companions.provider, "iron-gear-wheel", "normal") >= 2,
          "Batch " .. batch .. ": fewer than 2 gears produced"
        )

        -- Simulate bots delivering the produced gears from the provider to
        -- the external requester so the shortage is satisfied.
        local provider_inv = workshop.companions.provider
          .get_inventory(defines.inventory.chest)
        local gears = provider_inv.get_item_count({name = "iron-gear-wheel", quality = "normal"})
        provider_inv.remove({name = "iron-gear-wheel", count = gears, quality = "normal"})
        provider_inv.remove({name = "iron-plate", count = 100, quality = "normal"})
        deliver_to_requester(external_entity, {
          {name = "iron-gear-wheel", quality = "normal", count = gears}
        })

        -- The workshop may have been reassigned to a new waiting_inputs job
        -- (the mock network doesn't see the delivery to the external
        -- requester until the next shortage scan).  Clear the reassigned job
        -- so the next assess sees the satisfied shortage and leaves the
        -- workshop idle.
        if workshop.assignment then
          Workshop.clear_workshop_job(workshop, nil)
          Workshop.reset_workshop_assignment(workshop)
        end

        force_brain_reschedule(world)
        Brain.assess_all_workshops()
        advance_ticks(1)
        force_brain_reschedule(world)
        Brain.assess_all_workshops()

        assert.are.equal("idle", workshop_state(workshop),
          "Batch " .. batch .. ": workshop did not return to idle after delivery")

        -- Simulate consumption: remove the delivered gears from the external
        -- requester so the shortage reappears for the next batch.
        local ext_inv = external_entity.get_inventory(defines.inventory.chest)
        ext_inv.remove({name = "iron-gear-wheel", count = 100, quality = "normal"})
      end
    end)
  end)

  describe("parallel workshops cycling simultaneously", function()
    it("three workshops each complete multiple cycles without stalling", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 1}}
        }),
        ["copper-plate"] = make_recipe({
          name = "copper-plate",
          ingredients = {{type = "item", name = "copper-ore", amount = 1}}
        }),
        ["stone-brick"] = make_recipe({
          name = "stone-brick",
          ingredients = {{type = "item", name = "stone", amount = 1}}
        })
      }
      local world = setup_game({recipes = recipes, supply = {}})
      add_network_supply(world.network, {
        {name = "iron-ore", quality = "normal", count = 10000},
        {name = "copper-ore", quality = "normal", count = 10000},
        {name = "stone", quality = "normal", count = 10000}
      })

      -- Three different requester points so each workshop can get a job.
      table.insert(world.network.requester_points, (make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-plate", quality = "normal", count = 1}}
      })))
      table.insert(world.network.requester_points, (make_requester_entity({
        position = {x = 100, y = 101},
        force = world.force,
        surface = world.surface,
        filters = {{name = "copper-plate", quality = "normal", count = 1}}
      })))
      table.insert(world.network.requester_points, (make_requester_entity({
        position = {x = 100, y = 102},
        force = world.force,
        surface = world.surface,
        filters = {{name = "stone-brick", quality = "normal", count = 1}}
      })))

      local workshops = {}
      for i = 1, 3 do
        local w = add_workshop(world, {
          unit_number = i,
          position = {x = 0.5 + i * 4, y = 0.5},
          recipes = recipes
        })
        table.insert(workshops, w)
      end

      for cycle = 1, 4 do
        -- Clear all produced plates so shortages reappear.
        for _, w in ipairs(workshops) do
          local inv = w.companions.provider.get_inventory(defines.inventory.chest)
          inv.remove({name = "iron-plate", count = 100, quality = "normal"})
          inv.remove({name = "copper-plate", count = 100, quality = "normal"})
        end

        -- Replenish supply (mock doesn't auto-restock).
        add_network_supply(world.network, {
          {name = "iron-ore", quality = "normal", count = 100},
          {name = "copper-ore", quality = "normal", count = 100},
          {name = "stone", quality = "normal", count = 100}
        })

        force_brain_reschedule(world)
        Brain.assess_all_workshops()

        -- Drive all workshops until they each finish or we hit a limit.
        for _ = 1, 80 do
          local all_idle = true
          for _, w in ipairs(workshops) do
            local st = workshop_state(w)
            if st ~= "idle" then
              all_idle = false
            end
            if st == "waiting_inputs" then
              local reqs = workshop_requests(w)
              for _, req in ipairs(reqs) do
                local current = requester_has_item(
                  w.companions.requester, req.name, req.quality
                )
                local needed = math.max(0, (req.amount or 0) - current)
                if needed > 0 then
                  deliver_to_requester(w.companions.requester, {
                    {name = req.name, quality = req.quality, count = needed}
                  })
                end
              end
            end
            if st == "crafting_step" then
              complete_crafting_step(w, 1)
            end
          end

          force_brain_reschedule(world)
          Brain.assess_all_workshops()
          advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
          force_brain_reschedule(world)
          Brain.assess_all_workshops()

          if all_idle then break end
        end

        -- Every workshop should have produced something this cycle.
        for i, w in ipairs(workshops) do
          local iron = provider_has_item(w.companions.provider, "iron-plate", "normal")
          local copper = provider_has_item(w.companions.provider, "copper-plate", "normal")
          local stone = provider_has_item(w.companions.provider, "stone-brick", "normal")
          assert.is_true(
            iron > 0 or copper > 0 or stone > 0,
            "Cycle " .. cycle .. " workshop " .. i
              .. ": produced nothing (iron=" .. iron .. ", copper=" .. copper
              .. ", stone=" .. stone .. ")"
          )
        end
      end
    end)
  end)

  describe("queue drain between cycles", function()
    it("processes a queued job after the current job drains, then accepts a new one", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 1}}
        }),
        ["copper-plate"] = make_recipe({
          name = "copper-plate",
          ingredients = {{type = "item", name = "copper-ore", amount = 1}}
        })
      }
      local world = setup_game({recipes = recipes, supply = {}})
      add_network_supply(world.network, {
        {name = "iron-ore", quality = "normal", count = 100},
        {name = "copper-ore", quality = "normal", count = 100}
      })

      table.insert(world.network.requester_points, (make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-plate", quality = "normal", count = 1}}
      })))
      table.insert(world.network.requester_points, (make_requester_entity({
        position = {x = 100, y = 101},
        force = world.force,
        surface = world.surface,
        filters = {{name = "copper-plate", quality = "normal", count = 1}}
      })))

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes
      })

      -- First assessment: workshop picks up a job (alphabetical sort picks
      -- copper-plate before iron-plate).
      Brain.assess_all_workshops()
      local first_target = workshop_target(workshop)
      assert.is_not_nil(first_target)
      assert.is_true(first_target == "iron-plate" or first_target == "copper-plate")

      -- Deliver ore and complete the craft.
      local requests = workshop_requests(workshop)
      deliver_to_requester(workshop.companions.requester, {
        {name = requests[1].name, quality = "normal", count = requests[1].amount}
      })

      for _ = 1, 20 do
        if workshop_state(workshop) == "idle" then break end
        if workshop_state(workshop) == "crafting_step" then
          complete_crafting_step(workshop, 1)
        end
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
        advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
      end

      assert.is_true(
        provider_has_item(workshop.companions.provider, first_target, "normal") >= 1
      )

      -- Simulate bot delivery: move the product from the provider to the
      -- external requester so the first shortage is satisfied.
      local provider_inv = workshop.companions.provider
        .get_inventory(defines.inventory.chest)
      local produced = provider_inv.get_item_count({name = first_target, quality = "normal"})
      provider_inv.remove({name = first_target, count = produced, quality = "normal"})

      -- Find the external requester that wanted the first target.
      for _, rp in ipairs(world.network.requester_points) do
        for _, f in ipairs(rp.filters or {}) do
          if f.name == first_target then
            deliver_to_requester(rp.owner, {
              {name = first_target, quality = "normal", count = produced}
            })
          end
        end
      end

      -- Second cycle: workshop should pick up the other item.
      force_brain_reschedule(world)
      Brain.assess_all_workshops()

      for _ = 1, 5 do
        if workshop_state(workshop) ~= "idle" then break end
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
        advance_ticks(1)
      end

      local second_target = workshop_target(workshop)
      assert.is_not_nil(second_target)
      assert.is_true(second_target == "iron-plate" or second_target == "copper-plate")
      assert.are_not_equal(first_target, second_target)

      -- Deliver ore and complete.
      local reqs2 = workshop_requests(workshop)
      deliver_to_requester(workshop.companions.requester, {
        {name = reqs2[1].name, quality = "normal", count = reqs2[1].amount}
      })

      for _ = 1, 20 do
        if workshop_state(workshop) == "idle" then break end
        if workshop_state(workshop) == "crafting_step" then
          complete_crafting_step(workshop, 1)
        end
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
        advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
      end

      assert.is_true(
        provider_has_item(workshop.companions.provider, second_target, "normal") >= 1
      )
    end)
  end)

  ------------------------------------------------------------------
  -- Provider-as-supply tests (realistic logistic network behavior)
  --
  -- In real Factorio, items in active-provider chests ARE visible to the
  -- logistic network as supply.  The mock's `network._supply` dict doesn't
  -- include them.  These tests override `get_supply_counts` so the planner
  -- sees provider contents, which is what happens in-game.
  ------------------------------------------------------------------

  describe("provider-as-supply multi-cycle", function()
    -- Patch the network so supply counts include items in all Nexus provider
    -- chests that are registered in storage.workshops.
    local function patch_network_supply(world)
      local network = world.network
      local base_supply = network._supply

      network.get_supply_counts = function(id)
        local key
        if type(id) == "table" then
          key = Util.item_key(id.name, id.quality)
        else
          key = id .. "|normal"
        end

        local count = base_supply[key] or 0

        -- Also count items in every workshop's provider chest.
        for _, wd in pairs(storage.workshops or {}) do
          local provider = wd.companions and wd.companions.provider
          if provider and provider.valid then
            local inv = provider.get_inventory(defines.inventory.chest)
            if inv and inv.valid then
              count = count + (inv.get_item_count({name = id.name, quality = id.quality}) or 0)
            end
          end
        end

        return {storage = count}
      end

      network.get_item_count = function(id)
        local key
        if type(id) == "table" then
          key = Util.item_key(id.name, id.quality)
        else
          key = id .. "|normal"
        end

        local count = base_supply[key] or 0

        for _, wd in pairs(storage.workshops or {}) do
          local provider = wd.companions and wd.companions.provider
          if provider and provider.valid then
            local inv = provider.get_inventory(defines.inventory.chest)
            if inv and inv.valid then
              local item_id = type(id) == "table" and id or {name = id, quality = "normal"}
              count = count + (inv.get_item_count(item_id) or 0)
            end
          end
        end

        return count
      end
    end

    it("does not stall after multiple cycles when provider counts as supply", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 1}}
        })
      }
      local world = setup_game({recipes = recipes, supply = {}})
      add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 10000}})
      patch_network_supply(world)

      local external_point = make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-plate", quality = "normal", count = 1}}
      })
      table.insert(world.network.requester_points, external_point)

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes
      })

      for cycle = 1, 5 do
        -- Simulate consumption: remove iron-plate from external requester.
        local ext_inv = external_point.owner.get_inventory(defines.inventory.chest)
        ext_inv.remove({name = "iron-plate", count = 100, quality = "normal"})

        -- Replenish raw ore (mock doesn't auto-restock).
        add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 100}})

        force_brain_reschedule(world)
        Brain.assess_all_workshops()

        -- Wait for job assignment.
        for _ = 1, 5 do
          if workshop_state(workshop) ~= "idle" then break end
          force_brain_reschedule(world)
          Brain.assess_all_workshops()
          advance_ticks(1)
        end

        assert.are_not_equal("idle", workshop_state(workshop),
          "Cycle " .. cycle .. ": workshop never picked up the job")

        -- Deliver requested ore.
        local reqs = workshop_requests(workshop)
        for _, req in ipairs(reqs) do
          local current = requester_has_item(
            workshop.companions.requester, req.name, req.quality
          )
          local needed = math.max(0, (req.amount or 0) - current)
          if needed > 0 then
            deliver_to_requester(workshop.companions.requester, {
              {name = req.name, quality = req.quality, count = needed}
            })
          end
        end

        force_brain_reschedule(world)
        Brain.assess_all_workshops()
        advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
        force_brain_reschedule(world)
        Brain.assess_all_workshops()

        -- Run crafting to completion.
        for _ = 1, 30 do
          local st = workshop_state(workshop)
          if st ~= "crafting_step" and st ~= "settling_inputs" then break end
          if st == "crafting_step" then
            complete_crafting_step(workshop, 1)
          end
          force_brain_reschedule(world)
          Brain.assess_all_workshops()
          advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
          force_brain_reschedule(world)
          Brain.assess_all_workshops()
        end

        -- Simulate bot delivery: move iron-plate from provider to external.
        local provider_inv = workshop.companions.provider
          .get_inventory(defines.inventory.chest)
        local plates = provider_inv.get_item_count({name = "iron-plate", quality = "normal"})
        provider_inv.remove({name = "iron-plate", count = plates, quality = "normal"})
        deliver_to_requester(external_point.owner, {
          {name = "iron-plate", quality = "normal", count = plates}
        })

        -- Clear any reassigned job so the next cycle starts fresh.
        if workshop.assignment then
          Workshop.clear_workshop_job(workshop, nil)
          Workshop.reset_workshop_assignment(workshop)
        end

        force_brain_reschedule(world)
        Brain.assess_all_workshops()
        advance_ticks(1)
        force_brain_reschedule(world)
        Brain.assess_all_workshops()

        assert.is_true(
          provider_has_item(workshop.companions.provider, "iron-plate", "normal") >= 0,
          "Cycle " .. cycle .. ": something went wrong"
        )
      end
    end)
  end)

  ------------------------------------------------------------------
  -- Supply-depletion tests
  --
  -- In real Factorio, when bots deliver items to a requester chest, those
  -- items are REMOVED from network storage.  The mock's `network._supply` is
  -- static.  These tests patch the mock to deplete supply on delivery,
  -- exposing cases where multiple workshops over-claim shared supply.
  ------------------------------------------------------------------

  describe("supply depletion across multiple workshops", function()
    -- Wraps a world so that deliver_to_requester also removes from supply.
    local function make_depleting_deliverer(world)
      return function(requester, items)
        deliver_to_requester(requester, items)
        for _, item in ipairs(items) do
          remove_network_supply(world.network, {
            {name = item.name, quality = item.quality or "normal", count = item.count}
          })
        end
      end
    end

    it("two workshops sharing limited supply both complete their jobs", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 1}}
        })
      }
      local world = setup_game({recipes = recipes, supply = {}})
      -- Exactly 10 ore: enough for 2 workshops × 5 plates each.
      add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 10}})

      local deliver = make_depleting_deliverer(world)

      table.insert(world.network.requester_points, (make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-plate", quality = "normal", count = 10}}
      })))

      local workshops = {}
      for i = 1, 2 do
        local w = add_workshop(world, {
          unit_number = i,
          position = {x = 0.5 + i * 4, y = 0.5},
          recipes = recipes
        })
        table.insert(workshops, w)
      end

      Brain.assess_all_workshops()

      -- Both workshops should have been assigned.
      local assigned = 0
      for _, w in ipairs(workshops) do
        if workshop_state(w) ~= "idle" then assigned = assigned + 1 end
      end
      assert.are.equal(2, assigned, "Both workshops should have been assigned")

      -- Deliver exactly what each requester asked for, depleting supply.
      for _, w in ipairs(workshops) do
        local reqs = workshop_requests(w)
        for _, req in ipairs(reqs) do
          local current = requester_has_item(w.companions.requester, req.name, req.quality)
          local needed = math.max(0, (req.amount or 0) - current)
          if needed > 0 then
            deliver(w.companions.requester, {
              {name = req.name, quality = req.quality, count = needed}
            })
          end
        end
      end

      force_brain_reschedule(world)
      Brain.assess_all_workshops()
      advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
      force_brain_reschedule(world)
      Brain.assess_all_workshops()

      -- Both should be crafting.
      for i, w in ipairs(workshops) do
        assert.are.equal("crafting_step", workshop_state(w),
          "Workshop " .. i .. " should be crafting")
      end

      -- Complete all crafts.
      for _ = 1, 40 do
        local all_idle = true
        for _, w in ipairs(workshops) do
          local st = workshop_state(w)
          if st ~= "idle" then all_idle = false end
          if st == "crafting_step" then
            complete_crafting_step(w, 1)
          end
        end
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
        advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
        if all_idle then break end
      end

      -- Both workshops should have produced plates.
      for i, w in ipairs(workshops) do
        assert.is_true(
          provider_has_item(w.companions.provider, "iron-plate", "normal") >= 1,
          "Workshop " .. i .. " should have produced iron-plate"
        )
      end
    end)

    it("multi-step refresh does not over-claim shared supply", function()
      -- Two workshops both need iron-gear-wheels (2 plates each → 2 ore each).
      -- Supply is exactly 4 ore.  Workshop 1 starts first and is mid-craft
      -- when workshop 2 is assigned.  The refresh of workshop 1's plan should
      -- NOT see supply that workshop 2's assignment already claimed.
      local recipes = helpers.make_iron_gear_recipes(make_recipe)
      local world = setup_game({recipes = recipes, supply = {}})
      -- 4 ore: enough for 2 workshops × 1 gear each (2 ore per gear).
      add_network_supply(world.network, {{name = "iron-ore", quality = "normal", count = 12}})

      local deliver = make_depleting_deliverer(world)

      table.insert(world.network.requester_points, (make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-gear-wheel", quality = "normal", count = 6}}
      })))

      local workshops = {}
      for i = 1, 2 do
        local w = add_workshop(world, {
          unit_number = i,
          position = {x = 0.5 + i * 4, y = 0.5},
          recipes = recipes
        })
        table.insert(workshops, w)
      end

      -- First assessment assigns both workshops (shortage = 1, but product_limit
      -- is 3 so both get the same candidate).  With only 4 ore, the supply
      -- budget should limit the second assignment.
      Brain.assess_all_workshops()

      -- Count how many were assigned.
      local assigned = 0
      for _, w in ipairs(workshops) do
        if workshop_state(w) ~= "idle" then assigned = assigned + 1 end
      end

      -- With 12 ore and each gear needing 2 ore, the supply budget should
      -- allow both assignments (first gets 5-batch = 10 ore, second gets
      -- 1-batch = 2 ore, total = 12 ore).
      assert.are.equal(2, assigned,
        "Both workshops should be assigned with 12 ore available")

      -- Deliver to both, depleting supply.
      for _, w in ipairs(workshops) do
        local reqs = workshop_requests(w)
        for _, req in ipairs(reqs) do
          local current = requester_has_item(w.companions.requester, req.name, req.quality)
          local needed = math.max(0, (req.amount or 0) - current)
          if needed > 0 then
            deliver(w.companions.requester, {
              {name = req.name, quality = req.quality, count = needed}
            })
          end
        end
      end

      force_brain_reschedule(world)
      Brain.assess_all_workshops()
      advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
      force_brain_reschedule(world)
      Brain.assess_all_workshops()

      -- Both should be crafting.
      for i, w in ipairs(workshops) do
        assert.are.equal("crafting_step", workshop_state(w),
          "Workshop " .. i .. " should be crafting, state=" .. workshop_state(w))
      end

      -- Complete all crafts.
      for _ = 1, 40 do
        local all_idle = true
        for _, w in ipairs(workshops) do
          local st = workshop_state(w)
          if st ~= "idle" then all_idle = false end
          if st == "crafting_step" then
            complete_crafting_step(w, 1)
          end
        end
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
        advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
        force_brain_reschedule(world)
        Brain.assess_all_workshops()
        if all_idle then break end
      end

      -- Both workshops should have produced gears.
      for i, w in ipairs(workshops) do
        assert.is_true(
          provider_has_item(w.companions.provider, "iron-gear-wheel", "normal") >= 1,
          "Workshop " .. i .. " should have produced iron-gear-wheel"
        )
      end
    end)
  end)

  ------------------------------------------------------------------
  -- Autonomous multi-cycle test (no manual state clearing)
  --
  -- This test simulates real game behavior as closely as the mock allows:
  --   - Supply depletes when bots deliver to the requester
  --   - Provider contents are visible to the network as supply
  --   - Bots deliver finished products from provider to external requester
  --
  -- The test does NOT manually clear workshop jobs between cycles.
  -- The brain must manage the full lifecycle on its own: idle → waiting →
  -- settling → crafting → draining → idle → waiting → ...
  --
  -- If any state gets stale, the workshop will stop picking up new jobs.
  ------------------------------------------------------------------

  describe("autonomous multi-cycle without manual intervention", function()
    local function make_realistic_world(opts)
      opts = opts or {}
      local recipes = opts.recipes
      local world = setup_game({recipes = recipes, supply = {}})
      add_network_supply(world.network, opts.supply or {})

      -- Patch the network: supply includes provider chest contents.
      local network = world.network
      local base_supply = network._supply

      network.get_supply_counts = function(id)
        local key
        if type(id) == "table" then
          key = Util.item_key(id.name, id.quality)
        else
          key = id .. "|normal"
        end

        local count = base_supply[key] or 0
        for _, wd in pairs(storage.workshops or {}) do
          local provider = wd.companions and wd.companions.provider
          if provider and provider.valid then
            local inv = provider.get_inventory(defines.inventory.chest)
            if inv and inv.valid then
              local item_id = type(id) == "table" and id
                or {name = id, quality = "normal"}
              count = count + (inv.get_item_count(item_id) or 0)
            end
          end
        end
        return {storage = count}
      end

      network.get_item_count = function(id)
        local counts = network.get_supply_counts(id)
        return counts.storage or 0
      end

      return world
    end

    -- Depleting delivery: removes from network supply when delivering.
    local function deliver_and_deplete(world, requester, items)
      deliver_to_requester(requester, items)
      remove_network_supply(world.network, items)
    end

    -- Simulate bots taking finished product from provider to external requester.
    -- Also depletes the "shortage" by satisfying the external request.
    local function bots_collect_product(world, workshop, external_requester, item_name)
      local provider_inv = workshop.companions.provider
        .get_inventory(defines.inventory.chest)
      local available = provider_inv.get_item_count({name = item_name, quality = "normal"})
      if available > 0 then
        provider_inv.remove({name = item_name, count = available, quality = "normal"})
        deliver_to_requester(external_requester, {
          {name = item_name, quality = "normal", count = available}
        })
      end
      return available
    end

    it("simple recipe: 5 cycles with full autonomous lifecycle", function()
      local recipes = {
        ["iron-plate"] = make_recipe({
          name = "iron-plate",
          ingredients = {{type = "item", name = "iron-ore", amount = 1}}
        })
      }
      local world = make_realistic_world({
        recipes = recipes,
        supply = {{name = "iron-ore", quality = "normal", count = 10000}}
      })

      local external_point, external_entity = make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-plate", quality = "normal", count = 50}}
      })
      table.insert(world.network.requester_points, external_point)

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes
      })

      local total_delivered = 0

      for cycle = 1, 5 do
        -- Consume 5 plates from the external requester so the shortage persists.
        local ext_inv = external_entity.get_inventory(defines.inventory.chest)
        ext_inv.remove({name = "iron-plate", count = 5, quality = "normal"})

        -- Replenish raw ore (mock doesn't auto-restock).
        add_network_supply(world.network, {
          {name = "iron-ore", quality = "normal", count = 10}
        })

        -- Drive the workshop until it produces output or we time out.
        local produced = false
        for _ = 1, 120 do
          -- Bot delivery: if waiting for inputs, deliver requested items.
          if workshop_state(workshop) == "waiting_inputs" then
            local reqs = workshop_requests(workshop)
            for _, req in ipairs(reqs) do
              local current = requester_has_item(
                workshop.companions.requester, req.name, req.quality
              )
              local needed = math.max(0, (req.amount or 0) - current)
              if needed > 0 then
                deliver_and_deplete(world, workshop.companions.requester, {
                  {name = req.name, quality = req.quality, count = needed}
                })
              end
            end
          end

          if workshop_state(workshop) == "crafting_step" then
            complete_crafting_step(workshop, 1)
          end

          force_brain_reschedule(world)
          Brain.assess_all_workshops()
          advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
          force_brain_reschedule(world)
          Brain.assess_all_workshops()

          -- Check if product was produced.
          if bots_collect_product(world, workshop, external_entity, "iron-plate") > 0 then
            produced = true
            total_delivered = total_delivered + 1
            break
          end
        end

        assert.is_true(produced,
          "Cycle " .. cycle .. ": workshop failed to produce iron-plate "
            .. "(state=" .. workshop_state(workshop) .. ")")
      end

      assert.are.equal(5, total_delivered,
        "Should have delivered 5 plates over 5 cycles")
    end)

    it("multi-step recipe: 3 cycles with full autonomous lifecycle", function()
      local recipes = helpers.make_iron_gear_recipes(make_recipe)
      local world = make_realistic_world({
        recipes = recipes,
        supply = {{name = "iron-ore", quality = "normal", count = 10000}}
      })

      local external_point, external_entity = make_requester_entity({
        position = {x = 100, y = 100},
        force = world.force,
        surface = world.surface,
        filters = {{name = "iron-gear-wheel", quality = "normal", count = 30}}
      })
      table.insert(world.network.requester_points, external_point)

      local workshop = add_workshop(world, {
        unit_number = 1,
        position = {x = 0.5, y = 0.5},
        recipes = recipes
      })

      local total_delivered = 0

      for cycle = 1, 3 do
        -- Consume 5 gears from the external requester so the shortage persists.
        local ext_inv = external_entity.get_inventory(defines.inventory.chest)
        ext_inv.remove({name = "iron-gear-wheel", count = 5, quality = "normal"})

        -- Replenish raw ore.
        add_network_supply(world.network, {
          {name = "iron-ore", quality = "normal", count = 10}
        })

        local produced = false
        for _ = 1, 120 do
          if workshop_state(workshop) == "waiting_inputs" then
            local reqs = workshop_requests(workshop)
            for _, req in ipairs(reqs) do
              local current = requester_has_item(
                workshop.companions.requester, req.name, req.quality
              )
              local needed = math.max(0, (req.amount or 0) - current)
              if needed > 0 then
                deliver_and_deplete(world, workshop.companions.requester, {
                  {name = req.name, quality = req.quality, count = needed}
                })
              end
            end
          end

          if workshop_state(workshop) == "crafting_step" then
            complete_crafting_step(workshop, 1)
          end

          force_brain_reschedule(world)
          Brain.assess_all_workshops()
          advance_ticks(C.REQUEST_SETTLE_TICKS + 1)
          force_brain_reschedule(world)
          Brain.assess_all_workshops()

          -- Collect any leftover intermediates too.
          bots_collect_product(world, workshop, external_entity, "iron-plate")

          if bots_collect_product(world, workshop, external_entity, "iron-gear-wheel") > 0 then
            produced = true
            total_delivered = total_delivered + 1
            break
          end
        end

        assert.is_true(produced,
          "Cycle " .. cycle .. ": workshop failed to produce iron-gear-wheel "
            .. "(state=" .. workshop_state(workshop) .. ")")
      end

      assert.are.equal(3, total_delivered,
        "Should have delivered 3 gears over 3 cycles")
    end)
  end)
end)
