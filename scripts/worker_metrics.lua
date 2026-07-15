-- Logistic Nexus
-- Worker metrics collection for brain diagnostics.

local Workshop = require("scripts.workshop")

local M = {}

------------------------------------------------------------
-- WORKER METRICS
------------------------------------------------------------

function M.collect(brain)
  local workers = {}

  for _, unit_number in ipairs(brain.workshops or {}) do
    local workshop_data = storage.workshops[unit_number]
    local assignment = workshop_data and workshop_data.assignment
    local metric = {
      unit_number = unit_number,
      state = assignment and assignment.state or "idle",
      target = assignment and assignment.item or nil,
      quality = assignment and assignment.quality or "normal",
      replans = assignment and assignment.replans or 0
    }

    if assignment and assignment.state == "waiting_inputs" then
      local requester = workshop_data.companions and workshop_data.companions.requester
      local present, incoming, uncovered = Workshop.assignment_delivery_progress(
        requester,
        assignment.requests
      )
      metric.present = present
      metric.incoming = incoming
      metric.missing = uncovered[1] and uncovered[1].name or nil
    end

    table.insert(workers, metric)
  end

  return workers
end

return M
