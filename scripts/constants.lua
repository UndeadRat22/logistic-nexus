-- Logistic Nexus
-- Shared constants.

local M = {}

M.WORKSHOP_NAME = "logistic-nexus-workshop"
M.MAP_DISPLAY_NAME = "logistic-nexus-map-display"
M.WORLD_DISPLAY_NAME = "logistic-nexus-world-display"
M.REQUESTER_NAME = "logistic-nexus-requester"
M.PROVIDER_NAME = "logistic-nexus-provider"
M.INPUT_INSERTER_NAME = "logistic-nexus-input-inserter"
M.OUTPUT_INSERTER_NAME = "logistic-nexus-output-inserter"
M.BARRELLED_RECIPE_PREFIX = "logistic-nexus-barrelled-"
M.EMPTY_BARREL_ITEM = "barrel"

M.ASSESS_INTERVAL = 120
M.DEFAULT_PRODUCT_LIMIT = 3
M.MAX_CIRCUIT_PRODUCT_LIMIT = 100
M.REQUEST_SLOT_CLEAR_COUNT = 100
M.CONSTRUCTION_RESERVATION_TTL = 1800
M.WAITING_INPUT_RECHECK_TICKS = 300
M.REQUEST_SETTLE_TICKS = 60
M.CONSTRUCTION_SCAN_INTERVAL = 300
M.CONSTRUCTION_SCAN_BLOCK_SIZE = 128
M.CONSTRUCTION_SCAN_BLOCKS_PER_TICK = 4
M.PREFLIGHT_REPLANS_PER_ASSESS = 4
M.IDLE_RESCAN_INTERVAL = 300

M.CONSTRUCTION_REQUEST_TYPES = {
  "entity-ghost",
  "tile-ghost",
  "item-request-proxy"
}

M.COMPANION_NAMES = {
  [M.REQUESTER_NAME] = true,
  [M.PROVIDER_NAME] = true,
  [M.INPUT_INSERTER_NAME] = true,
  [M.OUTPUT_INSERTER_NAME] = true,
}

return M
