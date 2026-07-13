local helpers = require("spec.helpers")

helpers.install_globals()
local C = require("scripts.constants")

describe("constants workshop tiers", function()
  it("defines base and MK2 workshop names", function()
    assert.are.equal("logistic-nexus-workshop", C.WORKSHOP_NAME)
    assert.are.equal("logistic-nexus-workshop-mk2", C.WORKSHOP_MK2_NAME)
  end)

  it("includes both tiers in WORKSHOP_NAMES", function()
    assert.is_true(C.WORKSHOP_NAMES[C.WORKSHOP_NAME])
    assert.is_true(C.WORKSHOP_NAMES[C.WORKSHOP_MK2_NAME])
    assert.is_nil(C.WORKSHOP_NAMES["logistic-nexus-requester"])
  end)
end)
