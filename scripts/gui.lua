-- Logistic Nexus
-- Status GUI: network overview panel for players.

local Util = require("scripts.util")
local Storage = require("scripts.storage")

local M = {}

M.FRAME_NAME = "logistic-nexus-status-frame"
M.CLOSE_BUTTON_NAME = "logistic-nexus-status-close"

------------------------------------------------------------
-- BRAIN LOOKUP
------------------------------------------------------------

function M.get_brain_for_player(player)
  if not (player and player.valid and player.surface and player.force) then
    return nil
  end

  local network = player.surface.find_logistic_network_by_position(
    player.position,
    player.force
  )

  if not (network and network.valid) then
    return nil
  end

  Storage.init_brains()
  return storage.brains[Util.brain_key(network)]
end

------------------------------------------------------------
-- DATA PREPARATION
------------------------------------------------------------

function M.prepare_status_data(brain)
  local analysis = brain and brain.last_analysis or {}
  local targets = {}

  for _, target in ipairs(analysis.targets or {}) do
    table.insert(targets, {
      name = target.name,
      quality = target.quality or "normal",
      missing = target.missing or 0,
      available = target.available or 0,
      active = target.active or 0,
      remaining_units = target.remaining_units or 0,
      blocked_reason = target.blocked_reason,
      is_blocked = target.blocked_reason ~= nil
    })
  end

  local workers = {}
  for _, worker in ipairs(analysis.workers or {}) do
    table.insert(workers, {
      unit_number = worker.unit_number,
      state = worker.state,
      target = worker.target,
      quality = worker.quality or "normal",
      present = worker.present or 0,
      incoming = worker.incoming or 0,
      missing = worker.missing
    })
  end

  return {
    tick = analysis.tick or 0,
    total_workshops = analysis.total_workshops or 0,
    idle_workshops = analysis.idle_workshops or 0,
    assigned_workshops = analysis.assigned_workshops or 0,
    request_count = analysis.request_count or 0,
    shortage_count = analysis.shortage_count or 0,
    targets = targets,
    workers = workers
  }
end

------------------------------------------------------------
-- GUI LIFECYCLE
------------------------------------------------------------

function M.close_status_gui(player)
  local frame = player.gui.screen[M.FRAME_NAME]
  if frame and frame.valid then
    frame.destroy()
  end

  if player.opened and player.opened.valid
      and player.opened.name == M.FRAME_NAME then
    player.opened = nil
  end
end

local function add_title_bar(frame)
  local title_flow = frame.add({
    type = "flow",
    name = "title_flow",
    direction = "horizontal"
  })
  title_flow.drag_target = frame

  title_flow.add({
    type = "label",
    name = "title_label",
    caption = {"logistic-nexus.status-gui-title"},
    style = "frame_title"
  })

  local drag = title_flow.add({
    type = "empty-widget",
    name = "drag_handle",
    style = "draggable_space_header"
  })
  drag.drag_target = frame

  title_flow.add({
    type = "sprite-button",
    name = M.CLOSE_BUTTON_NAME,
    sprite = "utility/close",
    style = "frame_action_button",
    tooltip = {"logistic-nexus.status-gui-close"}
  })
end

local function add_summary(frame, data)
  local summary = frame.add({
    type = "label",
    name = "summary_label",
    caption = {
      "logistic-nexus.status-gui-summary",
      data.total_workshops,
      data.idle_workshops,
      data.assigned_workshops
    }
  })
  summary.style.single_line = false

  frame.add({
    type = "label",
    name = "request_label",
    caption = {
      "logistic-nexus.status-gui-requests",
      data.request_count,
      data.shortage_count
    }
  })
end

local function add_target_table(frame, data)
  frame.add({
    type = "label",
    name = "targets_header",
    caption = {"logistic-nexus.status-gui-targets"},
    style = "caption_label"
  })

  local scroll = frame.add({
    type = "scroll-pane",
    name = "targets_scroll",
    style = "scroll_pane"
  })
  scroll.style.maximal_height = 300

  local table_element = scroll.add({
    type = "table",
    name = "targets_table",
    column_count = 5,
    style = "slot_table"
  })

  table_element.add({type = "label", caption = {"logistic-nexus.status-gui-target-item"}})
  table_element.add({type = "label", caption = {"logistic-nexus.status-gui-target-missing"}})
  table_element.add({type = "label", caption = {"logistic-nexus.status-gui-target-available"}})
  table_element.add({type = "label", caption = {"logistic-nexus.status-gui-target-active"}})
  table_element.add({type = "label", caption = {"logistic-nexus.status-gui-target-status"}})

  for _, target in ipairs(data.targets) do
    local display_name = Util.status_item_name(target.name, target.quality)
    table_element.add({
      type = "label",
      caption = display_name
    })
    table_element.add({type = "label", caption = tostring(target.missing)})
    table_element.add({type = "label", caption = tostring(target.available)})
    table_element.add({type = "label", caption = tostring(target.active)})

    if target.is_blocked then
      table_element.add({
        type = "label",
        caption = {"logistic-nexus.status-gui-target-blocked", target.blocked_reason}
      })
    else
      table_element.add({
        type = "label",
        caption = {"logistic-nexus.status-gui-target-remaining", target.remaining_units}
      })
    end
  end
end

local function add_worker_table(frame, data)
  frame.add({
    type = "label",
    name = "workers_header",
    caption = {"logistic-nexus.status-gui-workers"},
    style = "caption_label"
  })

  local scroll = frame.add({
    type = "scroll-pane",
    name = "workers_scroll",
    style = "scroll_pane"
  })
  scroll.style.maximal_height = 200

  local table_element = scroll.add({
    type = "table",
    name = "workers_table",
    column_count = 5,
    style = "slot_table"
  })

  table_element.add({type = "label", caption = {"logistic-nexus.status-gui-worker-id"}})
  table_element.add({type = "label", caption = {"logistic-nexus.status-gui-worker-state"}})
  table_element.add({type = "label", caption = {"logistic-nexus.status-gui-worker-target"}})
  table_element.add({type = "label", caption = {"logistic-nexus.status-gui-worker-progress"}})
  table_element.add({type = "label", caption = {"logistic-nexus.status-gui-worker-missing"}})

  for _, worker in ipairs(data.workers) do
    table_element.add({type = "label", caption = "#" .. tostring(worker.unit_number)})
    table_element.add({type = "label", caption = tostring(worker.state)})

    local target = worker.target
        and Util.status_item_name(worker.target, worker.quality)
        or "-"
    table_element.add({type = "label", caption = target})

    local progress = "-"
    if worker.state == "waiting_inputs" then
      progress = tostring(worker.present) .. " + " .. tostring(worker.incoming)
    end
    table_element.add({type = "label", caption = progress})

    local missing = worker.missing or "-"
    table_element.add({type = "label", caption = missing})
  end
end

function M.open_status_gui(player, brain)
  M.close_status_gui(player)

  local data = M.prepare_status_data(brain)
  local frame = player.gui.screen.add({
    type = "frame",
    name = M.FRAME_NAME,
    caption = {"logistic-nexus.status-gui-title"},
    direction = "vertical"
  })

  frame.auto_center = true
  frame.style.minimal_width = 500

  add_title_bar(frame)
  add_summary(frame, data)

  if #data.targets > 0 then
    add_target_table(frame, data)
  end

  if #data.workers > 0 then
    add_worker_table(frame, data)
  end

  player.opened = frame
  return frame
end

return M
