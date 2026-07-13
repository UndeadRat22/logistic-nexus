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

describe("workshop entity prototype", function()
  before_each(function()
    reset_data()
    package.loaded["prototypes.entity"] = nil
  end)

  it("enables module slots and effects", function()
    require("prototypes.entity")

    local workshop = data.raw["assembling-machine"]["logistic-nexus-workshop"]
    assert.is_not_nil(workshop)
    assert.are.equal(4, workshop.module_slots)
    assert.are.same({"consumption", "speed", "productivity", "pollution"}, workshop.allowed_effects)
  end)

  it("allows blueprint copy-paste", function()
    require("prototypes.entity")

    local workshop = data.raw["assembling-machine"]["logistic-nexus-workshop"]
    assert.is_not_nil(workshop)
    assert.is_true(workshop.allow_copy_paste)

    local mk2 = data.raw["assembling-machine"]["logistic-nexus-workshop-mk2"]
    assert.is_not_nil(mk2)
    assert.is_true(mk2.allow_copy_paste)
  end)

  it("creates an MK2 tier with faster speed and more module slots", function()
    require("prototypes.entity")

    local mk2 = data.raw["assembling-machine"]["logistic-nexus-workshop-mk2"]
    assert.is_not_nil(mk2)
    assert.are.equal(2, mk2.crafting_speed)
    assert.are.equal(6, mk2.module_slots)
    assert.are.equal("1500kW", mk2.energy_usage)
    assert.is_nil(mk2.next_upgrade)

    local base = data.raw["assembling-machine"]["logistic-nexus-workshop"]
    assert.are.equal("logistic-nexus-workshop-mk2", base.next_upgrade)
  end)
end)
