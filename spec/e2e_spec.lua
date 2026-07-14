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
    it("BUG: preflight replan stalls the workshop after ingredients are delivered", function()
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

  describe("multi-step internal crafting", function()
    it("crafts intermediates internally and only requests leaves from the network", function()
      local recipes = {
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

  describe("known bugs", function()
    it("BUG: extra items in requester permanently stall waiting_inputs", function()
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
end)
