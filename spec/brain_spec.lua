local helpers = require("spec.helpers")

helpers.install_globals()
helpers.install_workshop_stubs()

local Storage = require("scripts.storage")
local Workshop = require("scripts.workshop")
local Brain = require("scripts.brain")

describe("brain", function()
  describe("candidate_choice_sort", function()
    it("prioritizes mall shortages", function()
      local a = {shortage = {name = "iron-plate"}, machine_count = 0, remaining_units = 5}
      local b = {shortage = {name = "logistic-nexus-workshop"}, machine_count = 0, remaining_units = 5}
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
      local mall = {shortage = {name = "logistic-nexus-workshop"}, machine_count = 10, remaining_units = 1}
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

  describe("clear_stale_recipe_cache", function()
    it("removes negative cache entries while keeping positive ones", function()
      local cached_recipe = {recipe_name = "iron-plate", product_amount = 1}
      local brain = {
        recipe_choices = {
          ["iron-plate"] = cached_recipe,
          ["copper-plate"] = false,
          ["steel-plate"] = false
        }
      }

      Brain.clear_stale_recipe_cache(brain)

      assert.are.equal(cached_recipe, brain.recipe_choices["iron-plate"])
      assert.is_nil(brain.recipe_choices["copper-plate"])
      assert.is_nil(brain.recipe_choices["steel-plate"])
    end)

    it("handles missing recipe_choices", function()
      local brain = {}
      assert.has_no.errors(function()
        Brain.clear_stale_recipe_cache(brain)
      end)
    end)
  end)

  describe("collect_worker_metrics", function()
    it("returns metrics for each workshop", function()
      storage.workshops = {
        [1] = {
          entity = {valid = true},
          assignment = {
            state = "crafting_step",
            item = "iron-plate",
            quality = "normal",
            replans = 2
          }
        },
        [2] = {
          entity = {valid = true},
          assignment = nil
        }
      }

      local brain = {workshops = {1, 2}}
      local workers = Brain.collect_worker_metrics(brain)

      assert.are.equal(2, #workers)
      assert.are.equal(1, workers[1].unit_number)
      assert.are.equal("crafting_step", workers[1].state)
      assert.are.equal("iron-plate", workers[1].target)
      assert.are.equal(2, workers[1].replans)
      assert.are.equal(2, workers[2].unit_number)
      assert.are.equal("idle", workers[2].state)
      assert.is_nil(workers[2].target)
    end)

    it("reports waiting_inputs progress", function()
      storage.workshops = {
        [1] = {
          entity = {valid = true},
          companions = {
            requester = {valid = true}
          },
          assignment = {
            state = "waiting_inputs",
            item = "copper-plate",
            quality = "normal",
            requests = {
              {name = "copper-ore", quality = "normal", amount = 10}
            }
          }
        }
      }

      local brain = {workshops = {1}}
      local workers = Brain.collect_worker_metrics(brain)

      assert.are.equal(1, #workers)
      assert.are.equal("waiting_inputs", workers[1].state)
    end)

    it("handles empty workshops list", function()
      local brain = {workshops = {}}
      local workers = Brain.collect_worker_metrics(brain)
      assert.are.same({}, workers)
    end)
  end)

  describe("brain_assess_tick_offset", function()
    it("returns a stable offset within the assess interval", function()
      local offset = Brain.brain_assess_tick_offset("player|1")
      assert.is_true(offset >= 0 and offset < 120)
      -- Stable: same key → same offset
      assert.are.equal(offset, Brain.brain_assess_tick_offset("player|1"))
    end)

    it("returns different offsets for different keys", function()
      local offsets = {}
      for i = 1, 20 do
        local offset = Brain.brain_assess_tick_offset("force|" .. i)
        offsets[offset] = true
      end
      -- At least 2 distinct offsets across 20 different keys
      local count = 0
      for _ in pairs(offsets) do count = count + 1 end
      assert.is_true(count >= 2)
    end)

    it("returns 0 for nil or empty key", function()
      assert.are.equal(0, Brain.brain_assess_tick_offset(nil))
      assert.are.equal(0, Brain.brain_assess_tick_offset(""))
    end)
  end)

  describe("process_due_brains", function()
    before_each(function()
      storage.brains = {}
      storage.workshops = {}
      Storage.preflight_replans_remaining = 4
    end)

    it("processes only brains whose tick offset matches the current tick", function()
      -- Two brains with different keys → different offsets.
      local net = {valid = true}
      storage.brains = {
        ["player|1"] = {
          key = "player|1",
          force_name = "player",
          network_id = 1,
          workshops = {1},
          recipe_choices = {},
          raw_supply_counts = {},
          next_schedule_tick = 0,
          network = net
        },
        ["player|2"] = {
          key = "player|2",
          force_name = "player",
          network_id = 2,
          workshops = {2},
          recipe_choices = {},
          raw_supply_counts = {},
          next_schedule_tick = 0,
          network = net
        }
      }

      local processed = {}
      local orig_process = Brain.process_brain
      Brain.process_brain = function(brain)
        table.insert(processed, brain.key)
      end

      -- Find a tick where only brain 1 is due, not brain 2.
      local offset1 = Brain.brain_assess_tick_offset("player|1")
      local offset2 = Brain.brain_assess_tick_offset("player|2")
      local tick = offset1
      while tick % 120 == offset2 do
        tick = tick + 120
      end

      game.tick = tick
      Brain.process_due_brains()

      Brain.process_brain = orig_process

      assert.are.equal(1, #processed)
      assert.are.equal("player|1", processed[1])
    end)

    it("skips brains with no workshops", function()
      storage.brains = {
        ["player|1"] = {
          key = "player|1",
          force_name = "player",
          network_id = 1,
          workshops = {},
          recipe_choices = {},
          raw_supply_counts = {},
          next_schedule_tick = 0,
          network = {valid = true}
        }
      }

      local processed = {}
      local orig_process = Brain.process_brain
      Brain.process_brain = function(brain)
        table.insert(processed, brain.key)
      end

      game.tick = Brain.brain_assess_tick_offset("player|1")
      Brain.process_due_brains()

      Brain.process_brain = orig_process
      assert.are.equal(0, #processed)
    end)

    it("removes brains with invalid network", function()
      storage.brains = {
        ["player|1"] = {
          key = "player|1",
          force_name = "player",
          network_id = 1,
          workshops = {1},
          recipe_choices = {},
          raw_supply_counts = {},
          next_schedule_tick = 0,
          network = {valid = false}
        }
      }

      local orig_process = Brain.process_brain
      Brain.process_brain = function() end

      game.tick = Brain.brain_assess_tick_offset("player|1")
      Brain.process_due_brains()

      Brain.process_brain = orig_process
      assert.is_nil(storage.brains["player|1"])
    end)

    it("ticks active workshops on non-due ticks", function()
      local offset = Brain.brain_assess_tick_offset("player|1")
      local non_due_tick = offset + 1
      if non_due_tick >= 120 then non_due_tick = non_due_tick - 120 end

      storage.brains = {
        ["player|1"] = {
          key = "player|1",
          force_name = "player",
          network_id = 1,
          workshops = {1},
          recipe_choices = {},
          raw_supply_counts = {},
          next_schedule_tick = 0,
          network = {valid = true}
        }
      }
      storage.workshops = {
        [1] = {
          entity = {valid = true},
          assignment = {state = "crafting_step", item = "iron-gear-wheel"}
        }
      }

      local ticked = {}
      local orig_tick = Workshop.tick_workshop_worker
      Workshop.tick_workshop_worker = function(ws_data, brain)
        table.insert(ticked, ws_data)
        return "working"
      end

      local process_called = false
      local orig_process = Brain.process_brain
      Brain.process_brain = function() process_called = true end

      game.tick = non_due_tick
      Brain.process_due_brains()

      Workshop.tick_workshop_worker = orig_tick
      Brain.process_brain = orig_process

      assert.is_false(process_called)
      assert.are.equal(1, #ticked)
    end)

    it("does not tick idle workshops on non-due ticks", function()
      local offset = Brain.brain_assess_tick_offset("player|1")
      local non_due_tick = offset + 1
      if non_due_tick >= 120 then non_due_tick = non_due_tick - 120 end

      storage.brains = {
        ["player|1"] = {
          key = "player|1",
          force_name = "player",
          network_id = 1,
          workshops = {1},
          recipe_choices = {},
          raw_supply_counts = {},
          next_schedule_tick = 0,
          network = {valid = true}
        }
      }
      storage.workshops = {
        [1] = {
          entity = {valid = true},
          assignment = nil
        }
      }

      local ticked = 0
      local orig_tick = Workshop.tick_workshop_worker
      Workshop.tick_workshop_worker = function() ticked = ticked + 1 return "idle" end

      local orig_process = Brain.process_brain
      Brain.process_brain = function() end

      game.tick = non_due_tick
      Brain.process_due_brains()

      Workshop.tick_workshop_worker = orig_tick
      Brain.process_brain = orig_process

      assert.are.equal(0, ticked)
    end)

    it("ticks active workshops on every consecutive tick", function()
      local offset = Brain.brain_assess_tick_offset("player|1")

      storage.brains = {
        ["player|1"] = {
          key = "player|1",
          force_name = "player",
          network_id = 1,
          workshops = {1},
          recipe_choices = {},
          raw_supply_counts = {},
          next_schedule_tick = 0,
          network = {valid = true}
        }
      }
      storage.workshops = {
        [1] = {
          entity = {valid = true},
          assignment = {state = "crafting_step", item = "iron-gear-wheel"}
        }
      }

      local tick_count = 0
      local orig_tick = Workshop.tick_workshop_worker
      Workshop.tick_workshop_worker = function() tick_count = tick_count + 1 return "working" end

      local orig_process = Brain.process_brain
      Brain.process_brain = function() end

      -- Run 10 consecutive ticks, skipping the one where the brain is due
      -- (process_brain would also tick there, so we stub it out to isolate).
      for t = 0, 9 do
        local tick = offset + 10 + t  -- offset+10..offset+19, none == offset
        game.tick = tick
        Brain.process_due_brains()
      end

      Workshop.tick_workshop_worker = orig_tick
      Brain.process_brain = orig_process

      -- All 10 non-due ticks should have ticked the active workshop
      assert.are.equal(10, tick_count)
    end)
  end)
end)
