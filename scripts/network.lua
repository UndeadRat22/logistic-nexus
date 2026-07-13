-- AG Mall
-- Logistic network queries: supply counts, requester points, inventory access.

local C = require("scripts.constants")
local Util = require("scripts.util")

local M = {}

------------------------------------------------------------
-- REQUESTER POINT ACCESS
------------------------------------------------------------

function M.get_requester_point(entity)
  if not (entity and entity.valid and entity.get_logistic_point) then
    return nil
  end

  local point = entity.get_logistic_point(defines.logistic_member_index.logistic_container)
  if not point then
    point = entity.get_logistic_point()
  end

  if point and point.valid then
    return point
  end

  return nil
end

function M.get_network_for_workshop(workshop_data)
  local workshop = workshop_data and workshop_data.entity
  local requester = workshop_data
      and workshop_data.companions
      and workshop_data.companions.requester

  local point = M.get_requester_point(requester)
  if point and point.logistic_network and point.logistic_network.valid then
    return point.logistic_network
  end

  if workshop and workshop.valid then
    return workshop.surface.find_logistic_network_by_position(workshop.position, workshop.force)
  end

  return nil
end

function M.is_internal_requester_owner(owner)
  return owner and owner.valid and owner.name == C.REQUESTER_NAME
end

------------------------------------------------------------
-- SUPPLY COUNTS
------------------------------------------------------------

function M.get_available_count(network, name, quality)
  local id = Util.item_id(name, quality)
  local ok, counts = pcall(function()
    return network.get_supply_counts(id)
  end)

  if ok and counts then
    return (counts.storage or 0)
        + (counts["passive-provider"] or 0)
        + (counts["active-provider"] or 0)
        + (counts.buffer or 0)
  end

  return network.get_item_count(id) or 0
end

function M.get_cached_supply_count(brain, network, name, quality)
  local key = Util.item_key(name, quality)

  if brain and brain.raw_supply_counts then
    if brain.raw_supply_counts[key] == nil then
      brain.raw_supply_counts[key] = M.get_available_count(network, name, quality)
    end

    return brain.raw_supply_counts[key]
  end

  return M.get_available_count(network, name, quality)
end

------------------------------------------------------------
-- INVENTORY ACCESS
------------------------------------------------------------

function M.get_item_count_from_inventory(owner, inventory_index, item)
  if not (owner and owner.valid and inventory_index) then
    return 0
  end

  local ok, inventory = pcall(function()
    return owner.get_inventory(inventory_index)
  end)

  if not (ok and inventory and inventory.valid) then
    return 0
  end

  return inventory.get_item_count(item) or 0
end

function M.get_requester_owner_item_count(owner, name, quality)
  local item = Util.item_id(name, quality)
  local inventory_index

  if owner.type == "character" then
    inventory_index = defines.inventory.character_main
  elseif owner.type == "spider-vehicle" then
    inventory_index = defines.inventory.spider_trunk
  elseif owner.type == "car" then
    inventory_index = defines.inventory.car_trunk
  elseif owner.type == "cargo-wagon" then
    inventory_index = defines.inventory.cargo_wagon
  elseif owner.type == "space-platform-hub" then
    inventory_index = defines.inventory.hub_main
  elseif owner.type == "cargo-landing-pad" then
    inventory_index = defines.inventory.cargo_landing_pad_main
  else
    inventory_index = defines.inventory.chest
  end

  return M.get_item_count_from_inventory(owner, inventory_index, item)
end

------------------------------------------------------------
-- DELIVERY TRACKING
------------------------------------------------------------

function M.targeted_delivery_count(point, name, quality)
  local count = 0

  for _, item in pairs(point and point.targeted_items_deliver or {}) do
    local item_quality = type(item.quality) == "string"
        and item.quality
        or (item.quality and item.quality.name)
        or "normal"
    if item.name == name
        and item_quality == (quality or "normal") then
      count = count + (item.count or 0)
    end
  end

  return count
end

------------------------------------------------------------
-- REQUESTER PLANNING COUNTS
------------------------------------------------------------

function M.requester_planning_counts(requester, include_incoming)
  local counts = {}
  local inventory = requester
      and requester.valid
      and requester.get_inventory(defines.inventory.chest)

  if inventory and inventory.valid then
    for _, item in pairs(inventory.get_contents() or {}) do
      Util.add_count(
        counts,
        item.name,
        item.count or 0,
        Util.quality_name(item.quality)
      )
    end
  end

  if include_incoming then
    local point = M.get_requester_point(requester)
    for _, item in pairs(point and point.targeted_items_deliver or {}) do
      Util.add_count(
        counts,
        item.name,
        item.count or 0,
        Util.quality_name(item.quality)
      )
    end
  end

  return counts
end

return M
