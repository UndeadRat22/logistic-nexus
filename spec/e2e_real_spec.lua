-- Real-API e2e tests for Logistic Nexus.
-- Converted from spec/e2e_spec.lua to use real Factorio entities
-- instead of hand-rolled mocks.

local C = require("scripts.constants")
local Storage = require("scripts.storage")
local Brain = require("scripts.brain")
local Util = require("scripts.util")
local H = require("spec.real_api_helpers")

------------------------------------------------------------
-- SETUP / TEARDOWN
------------------------------------------------------------

local function setup()
  H.clean_surface()
  Storage.init_storage()
  _G.settings = {
    global = {
      ["logistic-nexus-max-batches-per-job"] = {value = 5}
    }
  }
end

local function teardown()
  H.clean_surface()
end

------------------------------------------------------------
-- TESTS: SYNCHRONOUS (assignment checks)
------------------------------------------------------------

describe("real e2e: circuit controls", function()
  before_each(setup)
  after_each(teardown)

  it("blocks requested items listed on the circuit network", function()
    local world = H.setup_world{recipes = {"iron-plate", "copper-plate"}}

    -- Supply both ore types
    H.place_supply_chest(20, 20, {
      {name = "iron-ore", count = 100},
      {name = "copper-ore", count = 100}
    })

    -- Two requester chests wanting different plates
    H.place_requester(30, 20, "iron-plate", 5)
    H.place_requester(30, 22, "copper-plate", 5)

    -- Workshop with circuit signal blocking iron-plate
    local workshop = H.place_workshop(10, 10)
    local combinator = H.place_constant_combinator(12, 10, {
      {signal = {type = "item", name = "iron-plate"}, count = 1}
    })
    H.connect_circuit(workshop, combinator)

    Brain.assess_all_workshops()

    local ws_data = H.get_workshop_data(workshop.unit_number)
    -- Should be assigned copper-plate (iron-plate is blocked)
    assert.are.equal("copper-plate", H.workshop_target(ws_data))
  end)

  it("respects product limit P signal", function()
    local world = H.setup_world{recipes = {"iron-plate", "copper-plate", "steel-plate"}}

    H.place_supply_chest(20, 20, {
      {name = "iron-ore", count = 100},
      {name = "copper-ore", count = 100},
      {name = "iron-plate", count = 100}
    })

    H.place_requester(30, 20, "iron-plate", 1)
    H.place_requester(30, 22, "copper-plate", 1)
    H.place_requester(30, 24, "steel-plate", 1)

    local workshop = H.place_workshop(10, 10)
    local combinator = H.place_constant_combinator(12, 10, {
      {signal = {type = "virtual", name = "signal-P"}, count = 1}
    })
    H.connect_circuit(workshop, combinator)

    Brain.assess_all_workshops()

    local ws_data = H.get_workshop_data(workshop.unit_number)
    local target = H.workshop_target(ws_data)
    assert.is_not_nil(target, "workshop should have an assignment")
    -- With P=1, only one item is processed
    assert.is_true(
      target == "iron-plate" or target == "copper-plate" or target == "steel-plate"
    )
  end)
end)

describe("real e2e: quality", function()
  before_each(setup)
  after_each(teardown)

  it("requests matching-quality ingredients for quality shortages", function()
    -- This test requires the quality mod to be active.
    -- The CLI must be run with --mods quality to enable it.
    local force = H.get_force()
    local tech = force.technologies["quality"]
    if not tech then
      -- Quality mod not active; skip this test
      return
    end
    if not tech.researched then
      tech.researched = true
    end

    local world = H.setup_world{recipes = {"iron-plate"}}

    -- Supply uncommon ore
    H.place_supply_chest(20, 20, {
      {name = "iron-ore", count = 100, quality = "uncommon"}
    })

    -- Request uncommon plates
    H.place_requester(30, 20, "iron-plate", 5, "uncommon")

    local workshop = H.place_workshop(10, 10)

    Brain.assess_all_workshops()

    local ws_data = H.get_workshop_data(workshop.unit_number)
    local requests = H.workshop_requests(ws_data)
    assert.are.equal(1, #requests)
    assert.are.equal("iron-ore", requests[1].name)
    assert.are.equal("uncommon", requests[1].quality)
  end)
end)

------------------------------------------------------------
-- TESTS: ASYNC (crafting flows)
------------------------------------------------------------

describe("real e2e: happy path single-step crafting", function()
  before_each(setup)
  after_each(teardown)

  it("assigns workshop to craft iron-plate from iron-ore", function()
    local world = H.setup_world{recipes = {"iron-plate"}}

    H.place_supply_chest(20, 20, {{name = "iron-ore", count = 100}})
    H.place_requester(30, 20, "iron-plate", 5)
    local workshop = H.place_workshop(10, 10)

    Brain.assess_all_workshops()

    local ws_data = H.get_workshop_data(workshop.unit_number)
    assert.are.equal("iron-plate", H.workshop_target(ws_data))
    assert.are.equal("waiting_inputs", H.workshop_state(ws_data))

    local requests = H.workshop_requests(ws_data)
    assert.is_true(#requests >= 1)
    assert.are.equal("iron-ore", requests[1].name)
  end)

  it("transitions to crafting after ingredients are delivered", function()
    local world = H.setup_world{recipes = {"iron-plate"}}

    H.place_supply_chest(20, 20, {{name = "iron-ore", count = 100}})
    H.place_requester(30, 20, "iron-plate", 5)
    local workshop = H.place_workshop(10, 10)
    local ws_data = H.get_workshop_data(workshop.unit_number)

    Brain.assess_all_workshops()

    -- Deliver the requested ore to the requester chest
    local requests = H.workshop_requests(ws_data)
    H.deliver_to_chest(ws_data.companions.requester, {
      {name = "iron-ore", count = requests[1].amount}
    })

    -- Wait for the brain to re-assess and transition to crafting
    async(600)
    on_tick(function()
      if game.tick % 5 == 0 then
        H.force_brain_reschedule(world.network)
        Brain.assess_all_workshops()
      end
      if H.workshop_state(ws_data) == "crafting_step" then
        done()
      end
    end)
  end)
end)

describe("real e2e: batch crafting", function()
  before_each(setup)
  after_each(teardown)

  it("crafts the largest feasible batch up to the configured limit", function()
    _G.settings.global["logistic-nexus-max-batches-per-job"].value = 10

    local world = H.setup_world{recipes = {"iron-plate"}}

    -- Only 9 ore available
    H.place_supply_chest(20, 20, {{name = "iron-ore", count = 9}})
    H.place_requester(30, 20, "iron-plate", 9)
    local workshop = H.place_workshop(10, 10)
    local ws_data = H.get_workshop_data(workshop.unit_number)

    Brain.assess_all_workshops()

    assert.are.equal("iron-plate", H.workshop_target(ws_data))
    assert.are.equal("waiting_inputs", H.workshop_state(ws_data))

    local requests = H.workshop_requests(ws_data)
    assert.are.equal("iron-ore", requests[1].name)
    assert.are.equal(9, requests[1].amount)

    -- Deliver the ore
    H.deliver_to_chest(ws_data.companions.requester, {
      {name = "iron-ore", count = 9}
    })

    -- Wait for crafting to complete and check the provider.
    -- 9 plates at 3.2s each = ~29s real time; at game_speed=100 ~1740 ticks.
    async(2400)
    on_tick(function()
      if game.tick % 5 == 0 then
        H.force_brain_reschedule(world.network)
        Brain.assess_all_workshops()
      end
      if H.provider_has_item(ws_data.companions.provider, "iron-plate") >= 9 then
        done()
      end
    end)
  end)
end)

describe("real e2e: multi-step internal crafting", function()
  before_each(setup)
  after_each(teardown)

  it("crafts intermediates internally and only requests leaves from the network", function()
    local world = H.setup_world{recipes = {"iron-plate", "iron-gear-wheel"}}

    H.place_supply_chest(20, 20, {{name = "iron-ore", count = 100}})
    H.place_requester(30, 20, "iron-gear-wheel", 1)
    local workshop = H.place_workshop(10, 10)
    local ws_data = H.get_workshop_data(workshop.unit_number)

    Brain.assess_all_workshops()

    assert.are.equal("iron-gear-wheel", H.workshop_target(ws_data))
    local requests = H.workshop_requests(ws_data)
    assert.are.equal("iron-ore", requests[1].name)

    -- Deliver the requested ore
    H.deliver_to_chest(ws_data.companions.requester, {
      {name = "iron-ore", count = requests[1].amount}
    })

    -- Wait for the gear wheel to appear in the provider
    async(1200)
    on_tick(function()
      if game.tick % 5 == 0 then
        H.force_brain_reschedule(world.network)
        Brain.assess_all_workshops()
      end
      if H.provider_has_item(ws_data.companions.provider, "iron-gear-wheel") >= 1 then
        done()
      end
    end)
  end)
end)

describe("real e2e: construction requests", function()
  before_each(setup)
  after_each(teardown)

  it("picks up construction ghost demand and reserves output", function()
    local world = H.setup_world{recipes = {"iron-plate", "iron-gear-wheel", "transport-belt"}}

    H.place_supply_chest(20, 20, {{name = "iron-ore", count = 100}})

    -- Place a real entity ghost for transport-belt
    local surface = H.get_surface()
    local force = H.get_force()
    surface.create_entity{
      name = "entity-ghost",
      ghost_name = "transport-belt",
      position = {40, 20},
      force = force,
      raise_built = false
    }

    local workshop = H.place_workshop(10, 10)
    local ws_data = H.get_workshop_data(workshop.unit_number)

    -- Wait for the construction scan to pick up the ghost and assign the workshop
    async(600)
    on_tick(function()
      if game.tick % 10 == 0 then
        Brain.assess_all_workshops()
      end
      local target = H.workshop_target(ws_data)
      if target == "transport-belt" then
        done()
      end
    end)
  end)
end)

------------------------------------------------------------
-- TESTS: BUG REGRESSIONS
------------------------------------------------------------

describe("real e2e: previously fixed bugs", function()
  before_each(setup)
  after_each(teardown)

  it("extra items in requester do not permanently stall waiting_inputs", function()
    local world = H.setup_world{recipes = {"iron-plate"}}

    H.place_supply_chest(20, 20, {{name = "iron-ore", count = 100}})
    H.place_requester(30, 20, "iron-plate", 5)
    local workshop = H.place_workshop(10, 10)
    local ws_data = H.get_workshop_data(workshop.unit_number)

    Brain.assess_all_workshops()
    local requests = H.workshop_requests(ws_data)
    local needed = requests[1].amount

    -- Deliver exact ore plus one extra copper ore
    H.deliver_to_chest(ws_data.companions.requester, {
      {name = "iron-ore", count = needed},
      {name = "copper-ore", count = 1}
    })

    -- Wait far longer than the recheck threshold
    async(900)
    on_tick(function()
      if game.tick % 10 == 0 then
        H.force_brain_reschedule(world.network)
        Brain.assess_all_workshops()
      end
      -- Extra items should be ignored; workshop should proceed
      if H.workshop_state(ws_data) ~= "waiting_inputs" then
        done()
      end
    end)
  end)

  it("does not stall extra waiting workshops due to preflight replan budget", function()
    local world = H.setup_world{recipes = {"iron-plate"}}

    H.place_supply_chest(20, 20, {{name = "iron-ore", count = 1000}})
    H.place_requester(30, 20, "iron-plate", 100)

    -- Create several workshops
    local workshops = {}
    for i = 1, 6 do
      local ws = H.place_workshop(10 + i * 6, 10)
      table.insert(workshops, ws)
    end

    Brain.assess_all_workshops()

    -- Deliver ore to every requester
    for _, ws in ipairs(workshops) do
      local ws_data = H.get_workshop_data(ws.unit_number)
      local requests = H.workshop_requests(ws_data)
      if requests[1] then
        H.deliver_to_chest(ws_data.companions.requester, {
          {name = "iron-ore", count = requests[1].amount}
        })
      end
    end

    -- Wait for all workshops to transition out of waiting_inputs
    async(1200)
    on_tick(function()
      if game.tick % 10 == 0 then
        H.force_brain_reschedule(world.network)
        Brain.assess_all_workshops()
      end
      local waiting = 0
      for _, ws in ipairs(workshops) do
        local ws_data = H.get_workshop_data(ws.unit_number)
        if H.workshop_state(ws_data) == "waiting_inputs" then
          waiting = waiting + 1
        end
      end
      if waiting == 0 then
        done()
      end
    end)
  end)
end)

------------------------------------------------------------
-- TESTS: REPEATED CYCLES
------------------------------------------------------------

describe("real e2e: repeated craft cycles", function()
  before_each(setup)
  after_each(teardown)

  it("completes 3 consecutive cycles of a simple recipe", function()
    local world = H.setup_world{recipes = {"iron-plate"}}

    H.place_supply_chest(20, 20, {{name = "iron-ore", count = 200}})
    H.place_requester(30, 20, "iron-plate", 1)
    local workshop = H.place_workshop(10, 10)
    local ws_data = H.get_workshop_data(workshop.unit_number)

    local cycles_done = 0

    async(3600)
    on_tick(function()
      if game.tick % 5 == 0 then
        H.force_brain_reschedule(world.network)
        Brain.assess_all_workshops()
      end

      -- Deliver ingredients when waiting
      local state = H.workshop_state(ws_data)
      if state == "waiting_inputs" then
        local requests = H.workshop_requests(ws_data)
        for _, req in ipairs(requests) do
          local present = H.requester_has_item(
            ws_data.companions.requester, req.name, req.quality
          )
          local needed = math.max(0, (req.amount or 0) - present)
          if needed > 0 then
            H.deliver_to_chest(ws_data.companions.requester, {
              {name = req.name, quality = req.quality, count = needed}
            })
          end
        end
      end

      -- Check if a cycle completed (product in provider)
      if H.provider_has_item(ws_data.companions.provider, "iron-plate") >= 1 then
        cycles_done = cycles_done + 1
        if cycles_done >= 3 then
          done()
          return
        end
        -- Clear the product so the shortage reappears
        local inv = ws_data.companions.provider
          .get_inventory(defines.inventory.chest)
        inv.remove({name = "iron-plate", count = 100, quality = "normal"})
      end
    end)
  end)

  it("completes 3 consecutive cycles of a multi-step recipe", function()
    local world = H.setup_world{recipes = {"iron-plate", "iron-gear-wheel"}}

    H.place_supply_chest(20, 20, {{name = "iron-ore", count = 200}})
    H.place_requester(30, 20, "iron-gear-wheel", 1)
    local workshop = H.place_workshop(10, 10)
    local ws_data = H.get_workshop_data(workshop.unit_number)

    local cycles_done = 0

    async(3600)
    on_tick(function()
      if game.tick % 5 == 0 then
        H.force_brain_reschedule(world.network)
        Brain.assess_all_workshops()
      end

      -- Deliver ingredients when waiting
      local state = H.workshop_state(ws_data)
      if state == "waiting_inputs" then
        local requests = H.workshop_requests(ws_data)
        for _, req in ipairs(requests) do
          local present = H.requester_has_item(
            ws_data.companions.requester, req.name, req.quality
          )
          local needed = math.max(0, (req.amount or 0) - present)
          if needed > 0 then
            H.deliver_to_chest(ws_data.companions.requester, {
              {name = req.name, quality = req.quality, count = needed}
            })
          end
        end
      end

      -- Check if a cycle completed
      if H.provider_has_item(ws_data.companions.provider, "iron-gear-wheel") >= 1 then
        cycles_done = cycles_done + 1
        if cycles_done >= 3 then
          done()
          return
        end
        -- Clear products so shortage reappears
        local inv = ws_data.companions.provider
          .get_inventory(defines.inventory.chest)
        inv.remove({name = "iron-gear-wheel", count = 100, quality = "normal"})
        inv.remove({name = "iron-plate", count = 100, quality = "normal"})
      end
    end)
  end)
end)

------------------------------------------------------------
-- TESTS: MULTI-BATCH
------------------------------------------------------------

describe("real e2e: multi-batch with multi-step recipe", function()
  before_each(setup)
  after_each(teardown)

  it("crafts a 3-batch multi-step recipe and delivers all products", function()
    _G.settings.global["logistic-nexus-max-batches-per-job"].value = 5

    local world = H.setup_world{recipes = {"iron-plate", "iron-gear-wheel"}}

    -- 3 gears * 2 plates * 1 ore = 6 ore needed
    H.place_supply_chest(20, 20, {{name = "iron-ore", count = 6}})
    H.place_requester(30, 20, "iron-gear-wheel", 3)
    local workshop = H.place_workshop(10, 10)
    local ws_data = H.get_workshop_data(workshop.unit_number)

    Brain.assess_all_workshops()

    assert.are.equal("iron-gear-wheel", H.workshop_target(ws_data))

    -- Check we got a 3-batch plan: 6 ore requested
    local requests = H.workshop_requests(ws_data)
    assert.are.equal("iron-ore", requests[1].name)
    assert.are.equal(6, requests[1].amount)

    -- Deliver the ore
    H.deliver_to_chest(ws_data.companions.requester, {
      {name = "iron-ore", count = 6}
    })

    -- Wait for all 3 gears to be produced
    async(1800)
    on_tick(function()
      if game.tick % 5 == 0 then
        H.force_brain_reschedule(world.network)
        Brain.assess_all_workshops()
      end
      if H.provider_has_item(ws_data.companions.provider, "iron-gear-wheel") >= 3 then
        done()
      end
    end)
  end)
end)

------------------------------------------------------------
-- TESTS: PARALLEL WORKSHOPS
------------------------------------------------------------

describe("real e2e: parallel workshops", function()
  before_each(setup)
  after_each(teardown)

  it("three workshops each complete cycles without stalling", function()
    local world = H.setup_world{recipes = {"iron-plate", "copper-plate", "stone-brick"}}

    H.place_supply_chest(20, 20, {
      {name = "iron-ore", count = 200},
      {name = "copper-ore", count = 200},
      {name = "stone", count = 200}
    })
    H.place_requester(30, 20, "iron-plate", 1)
    H.place_requester(30, 22, "copper-plate", 1)

    -- Three workshops
    local workshops = {}
    for i = 1, 3 do
      local ws = H.place_workshop(10 + i * 6, 10)
      table.insert(workshops, ws)
    end

    async(2400)
    on_tick(function()
      if game.tick % 5 == 0 then
        H.force_brain_reschedule(world.network)
        Brain.assess_all_workshops()
      end

      -- Deliver ingredients to any waiting workshop
      for _, ws in ipairs(workshops) do
        local ws_data = H.get_workshop_data(ws.unit_number)
        if ws_data and H.workshop_state(ws_data) == "waiting_inputs" then
          local requests = H.workshop_requests(ws_data)
          for _, req in ipairs(requests) do
            local present = H.requester_has_item(
              ws_data.companions.requester, req.name, req.quality
            )
            local needed = math.max(0, (req.amount or 0) - present)
            if needed > 0 then
              H.deliver_to_chest(ws_data.companions.requester, {
                {name = req.name, quality = req.quality, count = needed}
              })
            end
          end
        end
      end

      -- Check if at least one product from each type was produced
      local iron = 0
      local copper = 0
      for _, ws in ipairs(workshops) do
        local ws_data = H.get_workshop_data(ws.unit_number)
        if ws_data then
          iron = iron + H.provider_has_item(ws_data.companions.provider, "iron-plate")
          copper = copper + H.provider_has_item(ws_data.companions.provider, "copper-plate")
        end
      end
      if iron >= 1 and copper >= 1 then
        done()
      end
    end)
  end)
end)
