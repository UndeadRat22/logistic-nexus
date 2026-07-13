-- Project-specific luacheck config for Logistic Nexus (Factorio 2.0)
-- Run: luacheck .

stds.factorio_data = {
  read_globals = {
    "mods",
    "feature_flags",
    "settings",
    "util",
  },
  globals = {
    -- `data` is fully mutable during the data stage.
    "data",
    -- Factorio helper tables created by the engine during data stage.
    "circuit_connector_definitions",
    "universal_connector_template",
  }
}

stds.factorio_control = {
  read_globals = {
    "commands",
    "defines",
    "game",
    "log",
    "rendering",
    "script",
    "settings",
  },
  globals = {
    -- `storage` is the persisted mod table in Factorio 2.0.
    "storage",
  }
}

stds.factorio_common = {
  read_globals = {
    "table",
    "string",
    "math",
  }
}

-- Default: control stage + common libraries.
std = "lua52+factorio_control+factorio_common"

-- Allow mutation of Factorio-managed globals.
allow_defined = true
allow_defined_top = true

-- Line length disabled; project already uses long lines.
max_line_length = false
max_code_line_length = false
max_string_line_length = false
max_comment_line_length = false

-- Unused variables/args/loop-vars starting with _ are intentional.
ignore = {"21[123]/_.*"}

-- Exclude generated or non-code paths and tests (tests mock globals).
exclude_files = {
  ".git/**",
  ".kimchi/**",
  "spec/**",
}

-- Data-stage files.
files["data.lua"].std = "lua52+factorio_data+factorio_common"
files["data-final-fixes.lua"].std = "lua52+factorio_data+factorio_common"
files["settings.lua"].std = "lua52+factorio_data+factorio_common"
files["prototypes/*.lua"].std = "lua52+factorio_data+factorio_common"

-- Control-stage files.
files["control.lua"].std = "lua52+factorio_control+factorio_common"
files["scripts/*.lua"].std = "lua52+factorio_control+factorio_common"
