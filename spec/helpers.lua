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

return M
