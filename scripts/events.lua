-- Logistic Nexus
-- Event handlers and command registration.

local C = require("scripts.constants")
local Storage = require("scripts.storage")
local Network = require("scripts.network")
local Construction = require("scripts.construction")
-- Loaded for side effects (event/command registration).
local Companions = require("scripts.companions") -- luacheck: ignore
local Brain = require("scripts.brain")
local Registration = require("scripts.registration")
local DebugCommands = require("scripts.debug_commands")
local Gui = require("scripts.gui")

local M = {}

------------------------------------------------------------
-- LIFECYCLE EVENTS
------------------------------------------------------------

function M.on_init()
  Storage.init_storage()
  Registration.sync_barrelled_recipes(nil, {reset_force_effects = true})
  Registration.rebuild_workshops()
end

function M.on_configuration_changed()
  Storage.init_storage()
  storage.construction_scans = {}
  storage.construction_scan_queue = {}
  storage.construction_scan_queue_first = 1
  storage.construction_scan_queue_last = 0
  storage.upgrade_marked = {}
  Registration.sync_barrelled_recipes(nil, {reset_force_effects = true})
  Registration.rebuild_workshops()
end

------------------------------------------------------------
-- BUILD/MINE EVENTS
------------------------------------------------------------

function M.on_built_entity(event)
  local entity = event.entity
  Construction.release_built_entity_construction_reservations(entity)

  if entity and entity.valid and C.WORKSHOP_NAMES[entity.name] then
    Registration.register_workshop(entity)
  end

  if entity and entity.valid and entity.surface and entity.force then
    Storage.mark_network_schedule_dirty(
      entity.surface.find_logistic_network_by_position(entity.position, entity.force)
    )
  end
end

function M.on_mined_entity(event)
  local entity = event.entity

  if not entity then
    return
  end

  if C.WORKSHOP_NAMES[entity.name] then
    Registration.unregister_workshop(entity, false)
  elseif C.COMPANION_NAMES[entity.name] then
    Registration.unregister_companion(entity)
  end

  Construction.unregister_upgrade_marked(entity)

  if entity.valid and entity.surface and entity.force then
    Storage.mark_network_schedule_dirty(
      entity.surface.find_logistic_network_by_position(entity.position, entity.force)
    )
  end
end

------------------------------------------------------------
-- UPGRADE EVENTS
------------------------------------------------------------

local function mark_entity_construction_network_dirty(entity)
  if not (entity and entity.valid and entity.surface and entity.force) then
    return
  end

  for _, network in pairs(
    entity.surface.find_logistic_networks_by_construction_area(
      entity.position,
      entity.force
    ) or {}
  ) do
    Storage.mark_network_schedule_dirty(network)
  end
end

function M.on_marked_for_upgrade(event)
  Construction.register_upgrade_marked(event.entity)
  mark_entity_construction_network_dirty(event.entity)
end

function M.on_cancelled_upgrade(event)
  Construction.unregister_upgrade_marked(event.entity)
  mark_entity_construction_network_dirty(event.entity)
end

------------------------------------------------------------
-- GUI / LOGISTIC / RESEARCH EVENTS
------------------------------------------------------------

function M.on_gui_opened(event)
  local entity = event.entity
  if not (entity and entity.valid and C.WORKSHOP_NAMES[entity.name]) then
    return
  end

  local player = game.get_player(event.player_index)
  if player then
    player.opened = nil
  end
end

function M.on_gui_click(event)
  local element = event.element
  if not (element and element.valid) then
    return
  end

  if element.name == Gui.CLOSE_BUTTON_NAME then
    local player = game.get_player(event.player_index)
    if player then
      Gui.close_status_gui(player)
    end
  end
end

function M.on_gui_closed(event)
  local element = event.element
  if not (element and element.valid) then
    return
  end

  if element.name == Gui.FRAME_NAME then
    local player = game.get_player(event.player_index)
    if player then
      Gui.close_status_gui(player)
    end
  end
end

function M.on_entity_logistic_slot_changed(event)
  local entity = event.entity
  if not (entity and entity.valid) or entity.name == C.REQUESTER_NAME then
    return
  end

  local point = Network.get_requester_point(entity)
  Storage.mark_network_schedule_dirty(point and point.logistic_network)
end

function M.on_research_finished(event)
  Registration.sync_barrelled_recipes(event.research and event.research.force)
end

function M.on_research_reversed(event)
  Registration.sync_barrelled_recipes(event.research and event.research.force)
end

function M.on_technology_effects_reset(event)
  Registration.sync_barrelled_recipes(event.force)
end

------------------------------------------------------------
-- TICK EVENTS
------------------------------------------------------------

function M.on_tick()
  Construction.process_construction_scan_queue()
  Brain.process_due_brains()
end

------------------------------------------------------------
-- REGISTRATION
------------------------------------------------------------

function M.register_events()
  script.on_init(M.on_init)
  script.on_configuration_changed(M.on_configuration_changed)

  script.on_event({
    defines.events.on_built_entity,
    defines.events.on_robot_built_entity,
    defines.events.script_raised_built,
    defines.events.script_raised_revive
  }, M.on_built_entity)

  script.on_event({
    defines.events.on_player_mined_entity,
    defines.events.on_robot_mined_entity,
    defines.events.on_entity_died,
    defines.events.script_raised_destroy
  }, M.on_mined_entity)

  if defines.events.on_marked_for_upgrade then
    script.on_event(defines.events.on_marked_for_upgrade, M.on_marked_for_upgrade)
  end

  if defines.events.on_cancelled_upgrade then
    script.on_event(defines.events.on_cancelled_upgrade, M.on_cancelled_upgrade)
  end

  script.on_event(defines.events.on_gui_opened, M.on_gui_opened)
  script.on_event(defines.events.on_gui_click, M.on_gui_click)

  if defines.events.on_gui_closed then
    script.on_event(defines.events.on_gui_closed, M.on_gui_closed)
  end

  script.on_event(defines.events.on_tick, M.on_tick)
  script.on_nth_tick(C.ASSESS_INTERVAL, Brain.assess_all_workshops)

  script.on_event(defines.events.on_entity_logistic_slot_changed, M.on_entity_logistic_slot_changed)

  script.on_event(defines.events.on_research_finished, M.on_research_finished)

  if defines.events.on_research_reversed then
    script.on_event(defines.events.on_research_reversed, M.on_research_reversed)
  end

  if defines.events.on_technology_effects_reset then
    script.on_event(defines.events.on_technology_effects_reset, M.on_technology_effects_reset)
  end

  commands.add_command("logistic-nexus-debug", "Print Logistic Nexus recipe debug for an item, for example: /logistic-nexus-debug concrete", function(command)
    local player = command.player_index and game.get_player(command.player_index)
    if not player then
      return
    end

    local item_name = command.parameter
    if not item_name or item_name == "" then
      item_name = "concrete"
    end

    DebugCommands.debug_mall_item(player, item_name)
  end)

  commands.add_command("logistic-nexus-debug-construction", "Print Logistic Nexus construction ghost debug for an item, for example: /logistic-nexus-debug-construction express-transport-belt", function(command)
    local player = command.player_index and game.get_player(command.player_index)
    if not player then
      return
    end

    local item_name = command.parameter
        and string.match(command.parameter, "^%s*(.-)%s*$")
        or ""
    if item_name == "" then
      player.print("Usage: /logistic-nexus-debug-construction item-name")
      return
    end

    DebugCommands.debug_construction_item(player, item_name)
  end)

  commands.add_command("logistic-nexus-status", "Print the latest Logistic Nexus network allocation analysis", function(command)
    DebugCommands.debug_status(command)
  end)

  commands.add_command("logistic-nexus-gui", "Open the Logistic Nexus status GUI", function(command)
    local player = command.player_index and game.get_player(command.player_index)
    if not player then
      return
    end

    local brain = Gui.get_brain_for_player(player)
    if brain then
      Gui.open_status_gui(player, brain)
    else
      player.print({"logistic-nexus.status-gui-no-network"})
    end
  end)
end

return M
