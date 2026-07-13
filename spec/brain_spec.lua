local helpers = require("spec.helpers")

helpers.install_globals()
local Brain = require("scripts.brain")

describe("brain", function()
  describe("candidate_choice_sort", function()
    it("prioritizes mall shortages", function()
      local a = {shortage = {name = "iron-plate"}, machine_count = 0, remaining_units = 5}
      local b = {shortage = {name = "ag-mall-workshop"}, machine_count = 0, remaining_units = 5}
      assert.is_true(Brain.candidate_choice_sort(b, a))
      assert.is_false(Brain.candidate_choice_sort(a, b))
    end)

    it("when both or neither are mall, sorts by machine_count ascending", function()
      local a = {shortage = {name = "iron-plate"}, machine_count = 3, remaining_units = 5}
      local b = {shortage = {name = "copper-plate"}, machine_count = 1, remaining_units = 5}
      assert.is_true(Brain.candidate_choice_sort(b, a))
      assert.is_false(Brain.candidate_choice_sort(a, b))
    end)

    it("when machine_count equal, sorts by remaining_units descending", function()
      local a = {shortage = {name = "iron-plate"}, machine_count = 2, remaining_units = 10}
      local b = {shortage = {name = "copper-plate"}, machine_count = 2, remaining_units = 5}
      assert.is_true(Brain.candidate_choice_sort(a, b))
      assert.is_false(Brain.candidate_choice_sort(b, a))
    end)

    it("when remaining_units equal, sorts by name ascending", function()
      local a = {shortage = {name = "copper-plate"}, machine_count = 2, remaining_units = 5}
      local b = {shortage = {name = "iron-plate"}, machine_count = 2, remaining_units = 5}
      assert.is_true(Brain.candidate_choice_sort(a, b))
      assert.is_false(Brain.candidate_choice_sort(b, a))
    end)

    it("mall item always wins regardless of other fields", function()
      local mall = {shortage = {name = "ag-mall-workshop"}, machine_count = 10, remaining_units = 1}
      local other = {shortage = {name = "iron-plate"}, machine_count = 0, remaining_units = 100}
      assert.is_true(Brain.candidate_choice_sort(mall, other))
      assert.is_false(Brain.candidate_choice_sort(other, mall))
    end)
  end)

  describe("collect_active_assignments", function()
    it("counts machines and outputs by item key", function()
      storage.workshops = {
        [1] = {
          assignment = {
            state = "waiting_inputs",
            item = "iron-plate",
            quality = "normal",
            expected_output = 2
          }
        },
        [2] = {
          assignment = {
            state = "crafting_step",
            item = "iron-plate",
            quality = "normal",
            expected_output = 2
          }
        },
        [3] = {
          assignment = {
            state = "draining",
            item = "copper-plate",
            quality = "normal",
            expected_output = 1
          }
        }
      }

      local brain = {workshops = {1, 2, 3}}
      local machines, outputs = Brain.collect_active_assignments(brain)

      assert.are.equal(2, machines["iron-plate|normal"])
      assert.are.equal(4, outputs["iron-plate|normal"])
      assert.is_nil(machines["copper-plate|normal"])
    end)

    it("skips workshops without assignment", function()
      storage.workshops = {
        [1] = {assignment = nil},
        [2] = {
          assignment = {
            state = "waiting_inputs",
            item = "iron-plate",
            quality = "normal",
            expected_output = 1
          }
        }
      }

      local brain = {workshops = {1, 2}}
      local machines, outputs = Brain.collect_active_assignments(brain)

      assert.are.equal(1, machines["iron-plate|normal"])
      assert.are.equal(1, outputs["iron-plate|normal"])
    end)

    it("handles empty workshops list", function()
      local brain = {workshops = {}}
      local machines, outputs = Brain.collect_active_assignments(brain)
      assert.are.same({}, machines)
      assert.are.same({}, outputs)
    end)
  end)
end)
