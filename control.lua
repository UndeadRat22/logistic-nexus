-- Logistic Nexus
-- Runtime entry point. All logic lives in scripts/modules.

local Events = require("scripts.events")

Events.register_events()

-- FactorioTest integration: only loads when the factorio-test mod is active.
if script.active_mods["factorio-test"] then
  require("__factorio-test__/init")(
    { "spec.real_api_tests", "spec.e2e_real_spec" },
    {
      load_luassert = true,
      game_speed = 100,
      default_timeout = 120 * 60,
    }
  )
end
