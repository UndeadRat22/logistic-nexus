-- Logistic Nexus
-- Construction scanning, reservations, and shortage collection.

local C = require("scripts.constants")
local Util = require("scripts.util")
local Storage = require("scripts.storage")
local Network = require("scripts.network")

local M = {}

------------------------------------------------------------
-- REQUEST AGGREGATION
------------------------------------------------------------

function M.add_requested_item(requested, entry)
  local key = Util.item_key(entry.name, entry.quality)
  local aggregate = requested[key]

  if not aggregate then
    aggregate = {
      name = entry.name,
      quality = entry.quality,
      requested = 0
    }
    requested[key] = aggregate
  end

  aggregate.requested = aggregate.requested + entry.requested
  aggregate.target = (aggregate.target or 0) + (entry.target or 0)
  aggregate.contents = (aggregate.contents or 0) + (entry.contents or 0)
  aggregate.incoming = (aggregate.incoming or 0) + (entry.incoming or 0)
  aggregate.construction_requested = (aggregate.construction_requested or 0)
      + (entry.construction_requested or 0)
end

------------------------------------------------------------
-- CONSTRUCTION RESERVATIONS
------------------------------------------------------------

function M.get_construction_reservation(network, name, quality, live_count)
  local key = Util.construction_reservation_key(network, name, quality)
  local reservations = Storage.get_construction_reservations()
  local reservation = reservations[key]

  if not reservation then
    return 0
  end

  if type(reservation.count) ~= "number" or type(reservation.tick) ~= "number" then
    reservations[key] = nil
    return 0
  end

  if type(live_count) ~= "number" then
    reservations[key] = nil
    return 0
  end

  if game.tick - (reservation.tick or 0) > C.CONSTRUCTION_RESERVATION_TTL then
    reservations[key] = nil
    return 0
  end

  reservation.count = math.min(reservation.count or 0, live_count)

  if reservation.count <= 0 then
    reservations[key] = nil
    return 0
  end

  return reservation.count
end

function M.prune_construction_reservations(network, live_counts)
  local prefix = network.network_id .. "|"
  local reservations = Storage.get_construction_reservations()

  for key, reservation in pairs(reservations) do
    if string.sub(key, 1, #prefix) == prefix then
      local live_count = live_counts[key] or 0

      if type(reservation) ~= "table"
          or type(reservation.count) ~= "number"
          or type(reservation.tick) ~= "number"
          or type(live_count) ~= "number"
          or live_count <= 0
          or game.tick - (reservation.tick or 0) > C.CONSTRUCTION_RESERVATION_TTL then
        reservations[key] = nil
      else
        reservation.count = math.min(reservation.count or 0, live_count)
      end
    end
  end
end

function M.reserve_construction_output(workshop_data, count)
  if not (workshop_data.current_is_construction and count and count > 0) then
    return
  end

  local network = Network.get_network_for_workshop(workshop_data)
  if not network then
    return
  end

  local quality = workshop_data.current_quality or "normal"
  local key = Util.construction_reservation_key(network, workshop_data.current_item, quality)
  local reservations = Storage.get_construction_reservations()
  local reservation = reservations[key]

  if not reservation then
    reservation = {
      count = 0,
      tick = game.tick
    }
    reservations[key] = reservation
  end

  local already_reserved = reservation.count or 0
  local remaining = (workshop_data.current_construction_target or 0) - already_reserved
  local reserved = math.min(count, math.max(0, remaining))

  if reserved <= 0 then
    return
  end

  reservation.count = (reservation.count or 0) + reserved
  reservation.tick = game.tick
  workshop_data.current_construction_reserved =
      (workshop_data.current_construction_reserved or 0) + reserved
end

function M.release_construction_reservation(network, name, quality, count)
  if not (network and network.valid and name and count and count > 0) then
    return
  end

  local reservations = Storage.get_construction_reservations()
  local key = Util.construction_reservation_key(network, name, quality)
  local reservation = reservations[key]

  if not reservation then
    return
  end

  reservation.count = (reservation.count or 0) - count

  if reservation.count <= 0 then
    reservations[key] = nil
  else
    reservation.tick = game.tick
  end
end

local function built_entity_place_item(entity)
  if not (entity and entity.valid and entity.prototype) then
    return nil
  end

  local items_to_place = entity.prototype.items_to_place_this
  return items_to_place and items_to_place[1] or nil
end

local function built_entity_quality(entity)
  local ok, quality = pcall(function()
    return entity.quality
  end)

  if ok then
    return Util.quality_name(quality)
  end

  return "normal"
end

function M.release_built_entity_construction_reservations(entity)
  local item = built_entity_place_item(entity)
  if not item then
    return
  end

  local surface = entity.surface
  local force = entity.force
  if not (surface and force) then
    return
  end

  local quality = built_entity_quality(entity)
  local count = item.count or 1

  for _, network in pairs(
    surface.find_logistic_networks_by_construction_area(entity.position, force) or {}
  ) do
    M.release_construction_reservation(network, item.name, quality, count)
    Storage.mark_network_schedule_dirty(network)
  end
end

------------------------------------------------------------
-- GHOST / UPGRADE / ITEM-REQUEST-PROXY HELPERS
------------------------------------------------------------

function M.ghost_key(entity)
  if entity.unit_number then
    return "u:" .. entity.unit_number
  end

  if entity.ghost_unit_number then
    return "g:" .. entity.ghost_unit_number
  end

  local position = entity.position
  return entity.name
      .. ":"
      .. (entity.ghost_name or "")
      .. ":"
      .. position.x
      .. ","
      .. position.y
end

local function add_construction_item_request(
    construction_counts,
    network,
    name,
    count,
    quality
  )
  quality = Util.quality_name(quality)

  if not (name and count and count > 0) then
    return false
  end

  local key = Util.construction_reservation_key(network, name, quality)
  local entry = construction_counts[key]

  if not entry then
    entry = {
      name = name,
      quality = quality,
      requested = 0
    }
    construction_counts[key] = entry
  end

  entry.requested = entry.requested + count
  return true
end

local function add_entity_ghost_request(construction_counts, network, ghost)
  if not (ghost
      and ghost.valid
      and ghost.type == "entity-ghost") then
    return false
  end

  local prototype = ghost.ghost_prototype
  if not prototype then
    return false
  end

  local added = false

  for _, item in pairs(prototype and prototype.items_to_place_this or {}) do
    if add_construction_item_request(
        construction_counts,
        network,
        item.name,
        item.count,
        ghost.quality
      ) then
      added = true
    end
  end

  return added
end

local function add_tile_ghost_request()
  return false
end

function M.add_ghost_request(construction_counts, network, ghost)
  if not (ghost and ghost.valid) then
    return false
  end

  if ghost.type == "entity-ghost" then
    return add_entity_ghost_request(construction_counts, network, ghost)
  end

  if ghost.type == "tile-ghost" then
    return add_tile_ghost_request(construction_counts, network, ghost)
  end

  return false
end

function M.add_item_request_proxy_requests(construction_counts, network, proxy)
  if not (proxy and proxy.valid and proxy.type == "item-request-proxy") then
    return false
  end

  local added = false

  for _, item in pairs(proxy.item_requests or {}) do
    if add_construction_item_request(
        construction_counts,
        network,
        item.name,
        item.count,
        item.quality
      ) then
      added = true
    end
  end

  return added
end

function M.entity_upgrade_target(entity)
  if not (entity and entity.valid) then
    return nil, nil
  end

  local ok_to_be_upgraded, to_be_upgraded = pcall(function()
    return entity.to_be_upgraded()
  end)
  if not ok_to_be_upgraded or not to_be_upgraded then
    return nil, nil
  end

  local ok, target, quality = pcall(function()
    return entity.get_upgrade_target()
  end)
  if not ok then
    return nil, nil
  end

  return target, quality
end

function M.add_upgrade_request(construction_counts, network, entity)
  local target, quality = M.entity_upgrade_target(entity)
  if not target then
    return false
  end

  local added = false

  for _, item in pairs(target.items_to_place_this or {}) do
    if add_construction_item_request(
        construction_counts,
        network,
        item.name,
        item.count,
        Util.quality_name(quality)
      ) then
      added = true
    end
  end

  return added
end

function M.construction_entity_items(entity)
  local items = {}

  if not (entity and entity.valid) then
    return items
  end

  if entity.type == "item-request-proxy" then
    for _, item in pairs(entity.item_requests or {}) do
      if item.name and item.count and item.count > 0 then
        table.insert(items, {
          name = item.name,
          count = item.count,
          quality = Util.quality_name(item.quality)
        })
      end
    end
    return items
  end

  local target, quality = M.entity_upgrade_target(entity)
  if target then
    for _, item in pairs(target.items_to_place_this or {}) do
      if item.name and item.count and item.count > 0 then
        table.insert(items, {
          name = item.name,
          count = item.count,
          quality = Util.quality_name(quality)
        })
      end
    end
    return items
  end

  if entity.type ~= "entity-ghost" then
    return items
  end

  local prototype = entity.ghost_prototype
  if not prototype then
    return items
  end

  for _, item in pairs(prototype.items_to_place_this or {}) do
    if item.name and item.count and item.count > 0 then
      table.insert(items, {
        name = item.name,
        count = item.count,
        quality = Util.quality_name(entity.quality)
      })
    end
  end

  return items
end

------------------------------------------------------------
-- CONSTRUCTION SCANNING
------------------------------------------------------------

function M.construction_scan_blocks(network)
  local surface
  local blocks = {}
  local seen = {}

  for _, cell in pairs(network.cells or {}) do
    local owner = cell and cell.valid and cell.owner
    if owner and owner.valid and cell.transmitting then
      local radius = cell.construction_radius or 0
      local position = owner.position
      surface = surface or owner.surface
      local min_x = math.floor((position.x - radius) / C.CONSTRUCTION_SCAN_BLOCK_SIZE)
      local min_y = math.floor((position.y - radius) / C.CONSTRUCTION_SCAN_BLOCK_SIZE)
      local max_x = math.floor((position.x + radius) / C.CONSTRUCTION_SCAN_BLOCK_SIZE)
      local max_y = math.floor((position.y + radius) / C.CONSTRUCTION_SCAN_BLOCK_SIZE)

      for block_x = min_x, max_x do
        for block_y = min_y, max_y do
          local key = block_x .. "," .. block_y
          if not seen[key] then
            seen[key] = true
            table.insert(blocks, {
              {
                block_x * C.CONSTRUCTION_SCAN_BLOCK_SIZE,
                block_y * C.CONSTRUCTION_SCAN_BLOCK_SIZE
              },
              {
                (block_x + 1) * C.CONSTRUCTION_SCAN_BLOCK_SIZE,
                (block_y + 1) * C.CONSTRUCTION_SCAN_BLOCK_SIZE
              }
            })
          end
        end
      end
    end
  end

  return surface, blocks
end

local function start_construction_scan(cache, network, surface, blocks)
  cache.scan = {
    surface_index = surface.index,
    force_name = network.force.name,
    network_id = network.network_id,
    blocks = blocks,
    block_index = 1,
    ghost_counts = {},
    request_count = 0,
    seen = {}
  }

  if not cache.queued then
    cache.queued = true
    local last = (storage.construction_scan_queue_last or #storage.construction_scan_queue) + 1
    storage.construction_scan_queue[last] = cache.key
    storage.construction_scan_queue_last = last
  end
end

function M.process_construction_scan_block(cache, network)
  local scan = cache.scan
  local surface = scan and game.surfaces[scan.surface_index]
  local area = scan and scan.blocks[scan.block_index]
  if not (scan and surface and network and network.valid and area) then
    cache.scan = nil
    cache.queued = false
    return false
  end

  for _, construction_entity in pairs(surface.find_entities_filtered({
    area = area,
    force = network.force,
    type = C.CONSTRUCTION_REQUEST_TYPES
  })) do
    if construction_entity.valid then
      local entity_key = M.ghost_key(construction_entity)
      if not scan.seen[entity_key] then
        local belongs_to_network = false

        for _, candidate_network in pairs(
          surface.find_logistic_networks_by_construction_area(
            construction_entity.position,
            network.force
          )
        ) do
          if candidate_network
              and candidate_network.valid
              and candidate_network.network_id == network.network_id then
            belongs_to_network = true
            break
          end
        end

        if belongs_to_network then
          scan.seen[entity_key] = true
          local added = construction_entity.type == "item-request-proxy"
              and M.add_item_request_proxy_requests(
                scan.ghost_counts,
                network,
                construction_entity
              )
              or M.add_ghost_request(
                scan.ghost_counts,
                network,
                construction_entity
              )

          if added then
            scan.request_count = scan.request_count + 1
          end
        end
      end
    end
  end

  for _, upgrade_entity in pairs(surface.find_entities_filtered({
    area = area,
    force = network.force
  })) do
    if upgrade_entity.valid then
      local target = M.entity_upgrade_target(upgrade_entity)
      if target then
        local entity_key = "upgrade:" .. M.ghost_key(upgrade_entity)
        if not scan.seen[entity_key] then
          local belongs_to_network = false

          for _, candidate_network in pairs(
            surface.find_logistic_networks_by_construction_area(
              upgrade_entity.position,
              network.force
            )
          ) do
            if candidate_network
                and candidate_network.valid
                and candidate_network.network_id == network.network_id then
              belongs_to_network = true
              break
            end
          end

          if belongs_to_network then
            scan.seen[entity_key] = true
            if M.add_upgrade_request(scan.ghost_counts, network, upgrade_entity) then
              scan.request_count = scan.request_count + 1
            end
          end
        end
      end
    end
  end

  scan.block_index = scan.block_index + 1
  if scan.block_index <= #scan.blocks then
    return true
  end

  cache.tick = game.tick
  cache.has_result = true
  cache.ghost_counts = scan.ghost_counts
  cache.request_count = scan.request_count
  cache.scan = nil
  cache.queued = false

  local brain = storage.brains
      and storage.brains[network.force.name .. "|" .. network.network_id]
  if brain then
    brain.schedule_dirty = true
    brain.next_schedule_tick = 0
  end

  return false
end

function M.process_construction_scan_queue()
  local queue = storage.construction_scan_queue
  if type(queue) ~= "table" then
    return
  end

  local first = storage.construction_scan_queue_first or 1
  local last = storage.construction_scan_queue_last or #queue
  if first > last then
    storage.construction_scan_queue = {}
    storage.construction_scan_queue_first = 1
    storage.construction_scan_queue_last = 0
    return
  end

  local budget = C.CONSTRUCTION_SCAN_BLOCKS_PER_TICK
  while budget > 0 and first <= last do
    local key = queue[first]
    queue[first] = nil
    first = first + 1

    local cache = storage.construction_scans[key]
    local scan = cache and cache.scan
    local brain = scan
        and storage.brains
        and storage.brains[scan.force_name .. "|" .. scan.network_id]
    local network = brain and brain.network

    if cache and scan and network and network.valid then
      local more = M.process_construction_scan_block(cache, network)
      if more then
        last = last + 1
        queue[last] = key
      end
    elseif cache then
      cache.scan = nil
      cache.queued = false
    end

    budget = budget - 1
  end

  if first > last then
    storage.construction_scan_queue = {}
    storage.construction_scan_queue_first = 1
    storage.construction_scan_queue_last = 0
  else
    storage.construction_scan_queue_first = first
    storage.construction_scan_queue_last = last
  end
end

function M.get_construction_scan(network)
  local surface
  for _, cell in pairs(network.cells or {}) do
    local owner = cell and cell.valid and cell.owner
    if owner and owner.valid then
      surface = owner.surface
      break
    end
  end

  if not surface then
    return nil
  end

  local key = Util.construction_scan_key(
    surface.index,
    network.force.name,
    network.network_id
  )
  local cache = storage.construction_scans[key]
  if not cache then
    cache = {
      key = key,
      network_id = network.network_id,
      tick = 0,
      has_result = false,
      ghost_counts = {},
      request_count = 0
    }
    storage.construction_scans[key] = cache
  end

  if not cache.scan
      and (
        not cache.has_result
        or game.tick - (cache.tick or 0) >= C.CONSTRUCTION_SCAN_INTERVAL
      ) then
    local _, blocks = M.construction_scan_blocks(network)
    start_construction_scan(cache, network, surface, blocks)
  end

  return cache
end

function M.collect_construction_requests(network, requested)
  local cache = M.get_construction_scan(network)
  local ghost_counts = cache and cache.ghost_counts or {}
  local request_count = cache and cache.request_count or 0

  for key, entry in pairs(ghost_counts) do
    local reserved = M.get_construction_reservation(
      network,
      entry.name,
      entry.quality,
      entry.requested
    )
    local needed = entry.requested - reserved

    if needed > 0 then
      M.add_requested_item(requested, {
        name = entry.name,
        quality = entry.quality,
        requested = needed,
        construction_requested = needed
      })
    end
  end

  if cache and cache.has_result then
    M.prune_construction_reservations(network, ghost_counts)
  end

  return request_count
end

------------------------------------------------------------
-- SHORTAGE COLLECTION
------------------------------------------------------------

function M.collect_shortages(network, brain)
  local requested = {}
  local request_count = 0

  for _, point in pairs(network.requester_points or {}) do
    if point
        and point.valid
        and point.enabled ~= false
        and not Network.is_internal_requester_owner(point.owner) then
      local point_requested = {}

      for _, filter in pairs(point.filters or {}) do
        local name = filter.name
        local quality = Util.quality_name(filter.quality)
        local count = filter.count or 0

        if (not filter.type or filter.type == "item")
            and name
            and count > 0 then
          local key = Util.item_key(name, quality)
          local entry = point_requested[key]

          if not entry then
            entry = {
              name = name,
              quality = quality,
              requested = 0
            }
            point_requested[key] = entry
          end

          entry.requested = entry.requested + count
          request_count = request_count + 1
        end
      end

      for _, entry in pairs(point_requested) do
        local contents = Network.get_requester_owner_item_count(point.owner, entry.name, entry.quality)
        local incoming = Network.targeted_delivery_count(point, entry.name, entry.quality)
        local unsatisfied = entry.requested - contents - incoming

        if unsatisfied > 0 then
          M.add_requested_item(requested, {
            name = entry.name,
            quality = entry.quality,
            requested = unsatisfied,
            target = entry.requested,
            contents = contents,
            incoming = incoming
          })
        end
      end
    end
  end

  request_count = request_count + M.collect_construction_requests(network, requested)

  local shortages = {}

  for _, entry in pairs(requested) do
    local missing = entry.requested

    if missing > 0 then
      entry.available = entry.contents or 0
      entry.missing = missing
      entry.construction_requested = math.min(
        entry.construction_requested or 0,
        missing
      )
      table.insert(shortages, entry)
    end
  end

  return shortages, request_count
end

function M.collect_prioritized_shortages(network, brain)
  local shortages, request_count = M.collect_shortages(network, brain)

  for _, shortage in pairs(shortages) do
    if shortage.name == C.WORKSHOP_NAME then
      shortage.priority = 4
    elseif (shortage.construction_requested or 0) > 0 then
      shortage.priority = 3
    else
      shortage.priority = 2
    end
  end

  table.sort(shortages, Util.shortage_sort)

  return shortages, {
    request_count = request_count,
    shortage_count = #shortages
  }
end

return M
