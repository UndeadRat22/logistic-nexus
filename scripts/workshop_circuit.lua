-- Logistic Nexus
-- Workshop circuit control signal reading.

local C = require("scripts.constants")

local M = {}

------------------------------------------------------------
-- CIRCUIT CONTROLS
------------------------------------------------------------

function M.read_workshop_circuit_controls(workshop)
  local controls = {
    excluded_items = {},
    product_limit = C.DEFAULT_PRODUCT_LIMIT
  }

  if not (workshop and workshop.valid) then
    return controls
  end

  local ok, signals = pcall(function()
    return workshop.get_signals(
      defines.wire_connector_id.circuit_red,
      defines.wire_connector_id.circuit_green
    )
  end)

  if not ok then
    return controls
  end

  for _, entry in pairs(signals or {}) do
    local signal = entry.signal
    local count = entry.count or 0

    if signal and count > 0 then
      if signal.type == "virtual" and signal.name == "signal-P" then
        controls.product_limit = math.max(
          1,
          math.min(C.MAX_CIRCUIT_PRODUCT_LIMIT, math.floor(count))
        )
      elseif (signal.type == nil or signal.type == "item") and signal.name then
        controls.excluded_items[signal.name] = true
      end
    end
  end

  return controls
end

return M
