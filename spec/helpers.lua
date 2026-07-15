-- Factorio API mocks for unit testing.
-- Stubs the global tables that Factorio scripts expect to find:
-- defines, storage, game, script, commands, rendering.

-- Deeply builds a nested table from a dot-separated path.
local function build_path(root, path)
  local current = root
  for part in string.gmatch(path, "[^%.]+") do
    current[part] = current[part] or {}
    current = current[part]
  end
  return current
end

local M = {}

-- Builds a `defines` table with nested sub-tables from dot paths.
-- e.g. M.make_defines({ "inventory.chest", "entity_status_diode.green" })
function M.make_defines(paths)
  local defines = {}
  for _, path in ipairs(paths) do
    build_path(defines, path)
  end
  return defines
end

-- The full set of defines paths used across all modules.
function M.default_defines()
  return M.make_defines({
    "inventory.chest",
    "inventory.character_main",
    "inventory.spider_trunk",
    "inventory.car_trunk",
    "inventory.cargo_wagon",
    "inventory.hub_main",
    "inventory.crafter_input",
    "entity_status_diode.green",
    "entity_status_diode.red",
    "entity_status_diode.yellow",
    "logistic_member_index.logistic_container",
    "wire_connector_id.circuit_red",
    "wire_connector_id.circuit_green",
    "events.on_built_entity",
    "events.on_robot_built_entity",
    "events.script_raised_built",
    "events.script_raised_revive",
    "events.on_player_mined_entity",
    "events.on_robot_mined_entity",
    "events.on_entity_died",
    "events.script_raised_destroy",
    "events.on_marked_for_upgrade",
    "events.on_cancelled_upgrade",
    "events.on_gui_opened",
    "events.on_tick",
    "events.on_entity_logistic_slot_changed",
    "events.on_research_finished",
    "events.on_research_reversed",
    "events.on_technology_effects_reset",
  })
end

-- Installs mock globals so that requiring a module does not error.
function M.install_globals()
  _G.defines = M.default_defines()
  _G.storage = {}
  _G.game = { tick = 0, surfaces = {}, forces = {} }
  _G.script = {}
  _G.commands = {}
  _G.rendering = {}
end

-- Removes the mock globals (call in after_each if needed).
function M.uninstall_globals()
  _G.defines = nil
  _G.storage = nil
  _G.game = nil
  _G.script = nil
  _G.commands = nil
  _G.rendering = nil
end

-- ------------------------------------------------------------------
-- Data-stage mocks (used by data-final-fixes and entity spec files)
-- ------------------------------------------------------------------

-- Minimal data-stage _G.util mock.
function M.install_data_stage_util()
  _G.util = {
    by_pixel = function(x, y)
      return {x / 32, y / 32}
    end
  }
  _G.circuit_connector_definitions = {
    create_vector = function() return {} end
  }
  _G.universal_connector_template = {}
end

-- Minimal deep_copy for _G.table.deepcopy.
local function deep_copy(original)
  local copy
  if type(original) == "table" then
    copy = {}
    for key, value in next, original, nil do
      copy[deep_copy(key)] = deep_copy(value)
    end
    setmetatable(copy, deep_copy(getmetatable(original)))
  else
    copy = original
  end
  return copy
end

-- Installs _G.table.deepcopy (call after install_globals).
function M.install_table_deepcopy()
  _G.table = _G.table or {}
  _G.table.deepcopy = deep_copy
end

-- Factory: base assembling-machine prototype.
function M.make_base_assembling_machine(name)
  return {
    type = "assembling-machine",
    name = name,
    flags = {},
    crafting_categories = {"crafting"},
    graphics_set = {
      animation = {
        layers = {
          {filename = ""},
          {filename = ""}
        }
      }
    }
  }
end

-- Factory: base logistic-container prototype.
function M.make_base_container(name)
  return {
    type = "logistic-container",
    name = name,
    flags = {}
  }
end

-- Factory: base inserter prototype.
function M.make_base_inserter(name)
  return {
    type = "inserter",
    name = name,
    flags = {}
  }
end

-- Builds a mock _G.data table with minimal raw prototypes.
-- Pass `recipes` to override the default recipe table.
function M.make_data_raw(recipes)
  _G.data = {
    raw = {
      recipe = recipes or {
        ["transport-belt"] = {
          type = "recipe",
          name = "transport-belt",
          category = "pressing",
          ingredients = {{type = "item", name = "iron-plate", amount = 1}},
          results = {{type = "item", name = "transport-belt", amount = 1}}
        },
        ["iron-plate"] = {
          type = "recipe",
          name = "iron-plate",
          category = "smelting",
          ingredients = {{type = "item", name = "iron-ore", amount = 1}},
          results = {{type = "item", name = "iron-plate", amount = 1}}
        }
      },
      technology = {},
      ["assembling-machine"] = {
        ["assembling-machine-1"] = M.make_base_assembling_machine("assembling-machine-1"),
        ["assembling-machine-3"] = M.make_base_assembling_machine("assembling-machine-3")
      },
      ["logistic-container"] = {
        ["requester-chest"] = M.make_base_container("requester-chest"),
        ["active-provider-chest"] = M.make_base_container("active-provider-chest")
      },
      ["inserter"] = {
        ["fast-inserter"] = M.make_base_inserter("fast-inserter")
      }
    },
    extend = function(self, entries)
      for _, entry in ipairs(entries) do
        local category = self.raw[entry.type]
        if not category then
          category = {}
          self.raw[entry.type] = category
        end
        category[entry.name] = entry
      end
    end
  }
end

-- Builds a mock _G.settings table.
function M.make_settings()
  _G.settings = {
    startup = {
      ["logistic-nexus-excluded-categories"] = {value = ""}
    }
  }
end

-- Helper: check if an entity has a crafting category.
function M.has_category(entity, category)
  for _, c in pairs(entity.crafting_categories or {}) do
    if c == category then
      return true
    end
  end
  return false
end

-- ------------------------------------------------------------------
-- Script-module stubs (shared by workshop_spec, circuit_controls_spec)
-- ------------------------------------------------------------------

-- Minimal Status stub for workshop tests.
function M.stub_status()
  return {
    set_idle_status = function() end,
    set_blocked_status = function() end,
    set_no_network_status = function() end,
    set_no_shortage_status = function() end,
    set_working_status = function() end,
    set_finishing_status = function() end,
    set_goal_sprite = function() end,
    destroy_goal_sprite = function() end
  }
end

-- Minimal Companions stub for workshop tests.
function M.stub_companions()
  return {
    set_requester_requests = function() return true end,
    clear_requester_requests = function() end,
    freeze_requester_batch = function() end
  }
end

-- Installs the common workshop module stubs into package.loaded.
-- Call before requiring "scripts.workshop".
function M.install_workshop_stubs()
  package.loaded["scripts.status"] = M.stub_status()
  package.loaded["scripts.companions"] = M.stub_companions()
end

-- ------------------------------------------------------------------
-- Test data builders (shared across spec files)
-- ------------------------------------------------------------------

-- Creates a storage.upgrade_marked table with one valid and one invalid entry.
function M.make_upgrade_marked_entries()
  return {
    [1] = {valid = true, unit_number = 1, surface = {index = 1}, position = {x = 0, y = 0}},
    [2] = {valid = false, unit_number = 2, surface = {index = 1}, position = {x = 0, y = 0}}
  }
end

-- Creates the standard iron-gear-wheel / iron-plate recipe pair used by
-- e2e_spec and planner_spec for internal crafting tests.
function M.make_iron_gear_recipes(make_recipe)
  return {
    ["iron-gear-wheel"] = make_recipe({
      name = "iron-gear-wheel",
      ingredients = {{type = "item", name = "iron-plate", amount = 2}}
    }),
    ["iron-plate"] = make_recipe({
      name = "iron-plate",
      ingredients = {{type = "item", name = "iron-ore", amount = 1}}
    })
  }
end

return M
