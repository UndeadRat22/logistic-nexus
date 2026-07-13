local helpers = require("spec.helpers")

helpers.install_globals()

-- Minimal data-stage mocks.
_G.util = {
  by_pixel = function(x, y)
    return {x / 32, y / 32}
  end
}

_G.circuit_connector_definitions = {
  create_vector = function()
    return {}
  end
}

_G.universal_connector_template = {}

local function deep_copy(original)
  local copy
  if type(original) == "table" then
    copy = {}
    for key, value in next, original, nil do
      copy[deep_copy(key)] = deep_copy(value)
    end
    setmetatable(copy, deep_copy(getmetatable(original)))
  else
    copy = original
  end
  return copy
end

_G.table.deepcopy = deep_copy

local function make_base_assembling_machine(name)
  return {
    type = "assembling-machine",
    name = name,
    flags = {},
    crafting_categories = {"crafting"},
    graphics_set = {
      animation = {
        layers = {
          {filename = ""},
          {filename = ""}
        }
      }
    }
  }
end

local function make_base_container(name)
  return {
    type = "logistic-container",
    name = name,
    flags = {}
  }
end

local function make_base_inserter(name)
  return {
    type = "inserter",
    name = name,
    flags = {}
  }
end

local function reset_data()
  _G.data = {
    raw = {
      recipe = {
        ["transport-belt"] = {
          type = "recipe",
          name = "transport-belt",
          category = "pressing",
          ingredients = {{type = "item", name = "iron-plate", amount = 1}},
          results = {{type = "item", name = "transport-belt", amount = 1}}
        },
        ["iron-plate"] = {
          type = "recipe",
          name = "iron-plate",
          category = "smelting",
          ingredients = {{type = "item", name = "iron-ore", amount = 1}},
          results = {{type = "item", name = "iron-plate", amount = 1}}
        }
      },
      technology = {},
      ["assembling-machine"] = {
        ["assembling-machine-1"] = make_base_assembling_machine("assembling-machine-1"),
        ["assembling-machine-3"] = make_base_assembling_machine("assembling-machine-3")
      },
      ["logistic-container"] = {
        ["requester-chest"] = make_base_container("requester-chest"),
        ["active-provider-chest"] = make_base_container("active-provider-chest")
      },
      ["inserter"] = {
        ["fast-inserter"] = make_base_inserter("fast-inserter")
      }
    },
    extend = function(self, entries)
      for _, entry in ipairs(entries) do
        local category = self.raw[entry.type]
        if not category then
          category = {}
          self.raw[entry.type] = category
        end
        category[entry.name] = entry
      end
    end
  }
end

local function reset_settings()
  _G.settings = {
    startup = {
      ["logistic-nexus-excluded-categories"] = {
        value = ""
      }
    }
  }
end

describe("data-final-fixes category collection", function()
  before_each(function()
    reset_data()
    reset_settings()
    package.loaded["prototypes.entity"] = nil
    package.loaded["prototypes.data_stage_util"] = nil
    package.loaded["data-final-fixes"] = nil
  end)

  it("adds mod recipe categories to both workshop tiers", function()
    require("prototypes.entity")
    require("data-final-fixes")

    local workshop = data.raw["assembling-machine"]["logistic-nexus-workshop"]
    local mk2 = data.raw["assembling-machine"]["logistic-nexus-workshop-mk2"]

    assert.is_not_nil(workshop)
    assert.is_not_nil(mk2)

    local function has_category(entity, category)
      for _, c in pairs(entity.crafting_categories or {}) do
        if c == category then
          return true
        end
      end
      return false
    end

    assert.is_true(has_category(workshop, "pressing"),
      "base workshop should support pressing category")
    assert.is_true(has_category(mk2, "pressing"),
      "MK2 workshop should support pressing category")
  end)

  it("respects excluded categories", function()
    settings.startup["logistic-nexus-excluded-categories"].value = "pressing"

    require("prototypes.entity")
    require("data-final-fixes")

    local workshop = data.raw["assembling-machine"]["logistic-nexus-workshop"]
    local mk2 = data.raw["assembling-machine"]["logistic-nexus-workshop-mk2"]

    local function has_category(entity, category)
      for _, c in pairs(entity.crafting_categories or {}) do
        if c == category then
          return true
        end
      end
      return false
    end

    assert.is_false(has_category(workshop, "pressing"))
    assert.is_false(has_category(mk2, "pressing"))
  end)

  it("collects alternate recipe categories", function()
    data.raw.recipe["transport-belt"].category = "crafting"
    data.raw.recipe["transport-belt"].categories = {"crafting", "pressing"}

    require("prototypes.entity")
    require("data-final-fixes")

    local workshop = data.raw["assembling-machine"]["logistic-nexus-workshop"]

    local function has_category(entity, category)
      for _, c in pairs(entity.crafting_categories or {}) do
        if c == category then
          return true
        end
      end
      return false
    end

    assert.is_true(has_category(workshop, "pressing"))
  end)

  it("inherits categories updated on the base assembling machine", function()
    -- Simulate Space Age updating assembling-machine-3 after our prototype was copied.
    data.raw["assembling-machine"]["assembling-machine-3"].crafting_categories = {
      "crafting",
      "pressing",
      "metallurgy"
    }

    require("prototypes.entity")
    require("data-final-fixes")

    local workshop = data.raw["assembling-machine"]["logistic-nexus-workshop"]

    local function has_category(entity, category)
      for _, c in pairs(entity.crafting_categories or {}) do
        if c == category then
          return true
        end
      end
      return false
    end

    assert.is_true(has_category(workshop, "pressing"))
    assert.is_true(has_category(workshop, "metallurgy"))
  end)
end)
