-- Logistic Nexus
-- Blocked-craft alerts: flying-text notifications for uncraftable items.

local C = require("scripts.constants")

local M = {}

------------------------------------------------------------
-- ALERT TRACKING
------------------------------------------------------------

function M.should_alert(brain, item_name, tick)
  if not (brain and item_name and tick) then
    return false
  end

  brain.last_alerts = brain.last_alerts or {}
  local last = brain.last_alerts[item_name]

  if not last then
    return true
  end

  return tick - last >= C.ALERT_COOLDOWN_TICKS
end

function M.record_alert(brain, item_name, tick)
  if not (brain and item_name and tick) then
    return
  end

  brain.last_alerts = brain.last_alerts or {}
  brain.last_alerts[item_name] = tick
end

------------------------------------------------------------
-- ALERT RENDERING
------------------------------------------------------------

function M.create_flying_text(workshop_data, item_name, reason)
  local workshop = workshop_data and workshop_data.entity
  if not (workshop and workshop.valid and workshop.surface) then
    return nil
  end

  local ok, entity = pcall(function()
    return workshop.surface.create_entity({
      name = "flying-text",
      position = workshop.position,
      text = {"logistic-nexus.alert-blocked", item_name, reason or "unknown"},
      color = {r = 1, g = 0.2, b = 0.2}
    })
  end)

  if ok then
    return entity
  end

  return nil
end

function M.alert_blocked_item(brain, workshop_data, item_name, reason, tick)
  if not M.should_alert(brain, item_name, tick) then
    return false
  end

  M.create_flying_text(workshop_data, item_name, reason)
  M.record_alert(brain, item_name, tick)
  return true
end

return M
