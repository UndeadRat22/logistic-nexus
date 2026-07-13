-- Data-stage helpers shared between prototype stage files.

local M = {}

-- Parses a comma-separated string of recipe category names into a lookup
-- table suitable for blacklisting categories from the AG Mall workshop.
function M.parse_excluded_categories(setting_value)
  local excluded = {}
  for entry in string.gmatch(setting_value or "", "[^,]+") do
    local category = string.match(entry, "^%s*(.-)%s*$")
    if category and category ~= "" then
      excluded[category] = true
    end
  end
  return excluded
end

return M
