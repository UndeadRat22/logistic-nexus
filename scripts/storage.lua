-- AG Mall
-- Storage initialization and shared mutable state.

local Util = require("scripts.util")

local M = {}

-- Shared mutable state (was file-level locals in original control.lua)
M.preflight_replans_remaining = 0

------------------------------------------------------------
-- STORAGE INITIALIZATION
------------------------------------------------------------

function M.init_storage()
  if type(storage.workshops) ~= "table" then
    storage.workshops = {}
  end
  if type(storage.companion_owners) ~= "table" then
    storage.companion_owners = {}
  end
  if type(storage.construction_reservations) ~= "table" then
    storage.construction_reservations = {}
  end
  if type(storage.brains) ~= "table" then
    storage.brains = {}
  end
  if type(storage.construction_scans) ~= "table" then
    storage.construction_scans = {}
  end
  if type(storage.construction_scan_queue) ~= "table" then
    storage.construction_scan_queue = {}
  end
  if type(storage.construction_scan_queue_first) ~= "number" then
    storage.construction_scan_queue_first = 1
  end
  if type(storage.construction_scan_queue_last) ~= "number" then
    storage.construction_scan_queue_last = #storage.construction_scan_queue
  end
  if type(storage.status_keys) ~= "table" then
    storage.status_keys = {}
  end
end

function M.get_construction_reservations()
  if type(storage.construction_reservations) ~= "table" then
    storage.construction_reservations = {}
  end

  return storage.construction_reservations
end

------------------------------------------------------------
-- BRAIN SCHEDULING
------------------------------------------------------------

function M.init_brains()
  if type(storage.brains) ~= "table" then
    storage.brains = {}
  end
end

function M.mark_network_schedule_dirty(network)
  if not (network and network.valid and storage.brains) then
    return
  end

  local brain = storage.brains[Util.brain_key(network)]
  if brain then
    brain.schedule_dirty = true
    brain.next_schedule_tick = 0
  end
end

return M
