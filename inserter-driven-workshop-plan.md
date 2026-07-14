# Inserter-Driven Logistic Nexus Workshop

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Lua inventory teleportation with physical inserter-driven item flow between the workshop, requester chest, and provider chest, then evolve the building toward a single, wireable workshop entity that reads network demand signals.

**Architecture:** The workshop stays an assembling-machine. Two (or three) invisible companion inserters are created alongside the existing requester/provider chests. Lua only decides *which* recipe to run and *which* filters to apply; vanilla inserters move the items. For multi-step internal crafting, a feedback inserter returns intermediate outputs from the provider chest back to the requester chest. Once Phase 1 is stable, Phase 2 collapses the companion chests into a single entity with built-in requester/provider cells that the player wires to external chests/belts.

**Tech Stack:** Factorio 2.0 Lua API, existing `busted` test suite, existing prototype/data-stage pipeline.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `prototypes/entity.lua` | Define companion inserter prototypes (already partially present). Add wire connection points, collision masks, and flags for the Phase 2 single-building entity. |
| `scripts/companions.lua` | Create/destroy companion inserters alongside requester/provider. Reuse existing layout helpers. |
| `scripts/workshop.lua` | Remove Lua item-teleport helpers (`move_requester_to_internal`, `insert_internal_to_workshop`, `collect_workshop_output_to_internal`, `output_internal_inventory`). Add inserter filter/stack-size management and new step-completion detection. |
| `scripts/brain.lua` | Keep scheduling unchanged; it only needs to hand a `job` to `Workshop`. |
| `scripts/planner.lua` | Keep plan generation unchanged; the plan still lists steps and leaf requests. |
| `scripts/construction.lua` | Keep reservation logic unchanged. |
| `scripts/events.lua` | Add event handlers for inserter/filter changes if needed for state detection. |
| `spec/e2e_spec.lua` | Update mock entities to support inserter objects and `inserter_behavior` filter API. |
| `spec/workshop_spec.lua` | Add tests for filter configuration, feedback loop, and step completion detection. |
| `inserter-driven-workshop-plan.md` | This document. |

---

## Phase 1: Inserter-Driven Companions

### Task 1: Create input and output inserter companions

**Files:**
- Modify: `scripts/companions.lua:21-49`
- Test: `spec/e2e_spec.lua` (mock `create_entity` must return inserter mocks)

- [ ] **Step 1: Add inserter specs to `companion_layout`**

```lua
function M.companion_layout(workshop)
  return {
    requester = M.companion_spec(workshop, C.REQUESTER_NAME, 1.5, 0.5),
    provider = M.companion_spec(workshop, C.PROVIDER_NAME, 1.5, 1.5),
    input_inserter = M.companion_spec(workshop, C.INPUT_INSERTER_NAME, 1.5, 0.5),
    output_inserter = M.companion_spec(workshop, C.OUTPUT_INSERTER_NAME, 1.5, 1.5)
  }
end
```

Use the existing prototype positions so the input inserter picks from the requester chest and drops into the workshop, and the output inserter picks from the workshop and drops into the provider chest. Adjust `pickup_position` and `insert_position` in the prototype or set them after creation.

- [ ] **Step 2: Update `ensure_companions` to create inserters**

Extend the creation loop to handle inserter companions. For each inserter, set:
- `pickup_target` / `drop_target` to the appropriate chest/workshop
- `use_filters = true`
- `allow_customization = false` (optional)

- [ ] **Step 3: Run existing tests**

Run: `busted spec`
Expected: PASS (with updated mocks)

- [ ] **Step 4: Commit**

```bash
git add scripts/companions.lua spec/e2e_spec.lua
git commit -m "feat(companions): create input/output inserter companions"
```

---

### Task 2: Configure inserter filters for the current crafting step

**Files:**
- Modify: `scripts/workshop.lua`
- Test: `spec/workshop_spec.lua`

- [ ] **Step 1: Add `M.apply_step_inserter_filters(workshop_data, step)`**

```lua
function M.apply_step_inserter_filters(workshop_data, step)
  local input_inserter = workshop_data.companions.input_inserter
  if not (input_inserter and input_inserter.valid) then
    return false
  end

  local behavior = input_inserter.get_control_behavior()
  if not behavior then
    behavior = input_inserter.get_or_create_control_behavior()
  end

  behavior.filters = {}
  for _, ingredient in ipairs(step.ingredients or {}) do
    table.insert(behavior.filters, {
      name = ingredient.name,
      quality = ingredient.quality or "normal",
      count = Util.ingredient_count(ingredient) or 1
    })
  end

  return true
end
```

- [ ] **Step 2: Call it from `start_next_internal_step` instead of `insert_internal_to_workshop`**

Replace:

```lua
if not M.insert_internal_to_workshop(workshop_data, assignment, step.ingredients) then
  return false
end
```

with:

```lua
if not M.apply_step_inserter_filters(workshop_data, step) then
  return false
end
```

- [ ] **Step 3: Write failing test**

```lua
it("sets input inserter filters for the current step", function()
  local filters_set = {}
  local inserter = {
    valid = true,
    name = C.INPUT_INSERTER_NAME,
    get_control_behavior = function()
      return {
        filters = filters_set
      }
    end,
    get_or_create_control_behavior = function()
      return {
        filters = filters_set
      }
    end
  }
  local workshop_data = make_workshop_data({
    companions = {
      input_inserter = inserter
    }
  })

  local ok = Workshop.apply_step_inserter_filters(workshop_data, {
    ingredients = {
      {name = "iron-plate", amount = 2, quality = "normal"}
    }
  })

  assert.is_true(ok)
  assert.are.equal(1, #filters_set)
  assert.are.equal("iron-plate", filters_set[1].name)
  assert.are.equal(2, filters_set[1].count)
end)
```

- [ ] **Step 4: Run test to verify it fails**

Run: `busted spec/workshop_spec.lua -v`
Expected: FAIL — `apply_step_inserter_filters` not defined

- [ ] **Step 5: Run test to verify it passes**

Run: `busted spec/workshop_spec.lua -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add scripts/workshop.lua spec/workshop_spec.lua
git commit -m "feat(workshop): configure input inserter filters per crafting step"
```

---

### Task 3: Detect step completion without Lua inventory checks

**Files:**
- Modify: `scripts/workshop.lua`
- Test: `spec/e2e_spec.lua`, `spec/workshop_spec.lua`

- [ ] **Step 1: Add `M.step_is_complete(workshop_data, assignment)`**

```lua
function M.step_is_complete(workshop_data, assignment)
  local workshop = workshop_data.entity
  if not (workshop and workshop.valid) then
    return false
  end

  local current_recipe, current_quality = workshop.get_recipe()
  local step = assignment.current_step
  if not step then
    return false
  end

  if not current_recipe or current_recipe.name ~= step.recipe_name then
    return false
  end

  local finished = workshop.products_finished or 0
  return finished >= (assignment.step_target_finished or finished)
end
```

- [ ] **Step 2: Update `tick_workshop_worker` crafting_step branch**

Replace the output-collection block with a check that waits for `step_is_complete`. Keep `products_finished` tracking.

```lua
if M.step_is_complete(workshop_data, assignment) then
  assignment.recorded_products_finished = workshop.products_finished or 0

  if M.continue_assignment_after_internal_change(workshop_data, assignment, brain) then
    Status.set_working_status(workshop, assignment.item, assignment.current_step_index or 1)
  else
    Status.set_blocked_status(workshop)
  end
  return "busy"
end
```

Do **not** call `collect_workshop_output_to_internal` — the output inserter will move items to the provider chest.

- [ ] **Step 3: Write e2e test for single-step completion**

Extend the existing happy-path e2e test. After delivering ingredients and advancing to `crafting_step`, simulate inserter movement by inserting the recipe output directly into the provider chest and incrementing `products_finished`. Assert the workshop transitions to `draining` and the output appears in the provider.

- [ ] **Step 4: Run tests**

Run: `busted spec`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/workshop.lua spec/e2e_spec.lua spec/workshop_spec.lua
git commit -m "feat(workshop): detect step completion via products_finished and inserters"
```

---

### Task 4: Add feedback inserter for internal intermediate crafting

**Files:**
- Modify: `scripts/companions.lua`, `prototypes/entity.lua`
- Modify: `scripts/workshop.lua`
- Test: `spec/e2e_spec.lua`

- [ ] **Step 1: Add feedback inserter prototype and companion spec**

In `prototypes/entity.lua`, add a third inserter from `fast-inserter`:

```lua
local feedback_inserter = table.deepcopy(data.raw["inserter"]["fast-inserter"])
feedback_inserter.name = "logistic-nexus-feedback-inserter"
-- ... existing flag setup like input/output inserters ...
```

Add it to `data:extend`. Add `FEEDBACK_INSERTER_NAME` to `scripts/constants.lua` and `COMPANION_NAMES`.

In `companions.lua`:

```lua
function M.companion_layout(workshop)
  return {
    requester = M.companion_spec(workshop, C.REQUESTER_NAME, 1.5, 0.5),
    provider = M.companion_spec(workshop, C.PROVIDER_NAME, 1.5, 1.5),
    input_inserter = M.companion_spec(workshop, C.INPUT_INSERTER_NAME, 1.5, 0.5),
    output_inserter = M.companion_spec(workshop, C.OUTPUT_INSERTER_NAME, 1.5, 1.5),
    feedback_inserter = M.companion_spec(workshop, C.FEEDBACK_INSERTER_NAME, 1.5, 1.5)
  }
end
```

Position the feedback inserter so it picks from the provider chest and drops into the requester chest.

- [ ] **Step 2: Add `M.apply_feedback_filter(workshop_data, next_step)`**

```lua
function M.apply_feedback_filter(workshop_data, next_step)
  local feedback = workshop_data.companions.feedback_inserter
  if not (feedback and feedback.valid) then
    return false
  end

  local behavior = feedback.get_control_behavior()
  if not behavior then
    behavior = feedback.get_or_create_control_behavior()
  end

  local needed = {}
  for _, ingredient in ipairs(next_step and next_step.ingredients or {}) do
    local key = Util.item_key(ingredient.name, ingredient.quality or "normal")
    needed[key] = (needed[key] or 0) + (Util.ingredient_count(ingredient) or 0)
  end

  behavior.filters = {}
  for key, count in pairs(needed) do
    local name, quality = Util.split_item_key(key)
    table.insert(behavior.filters, {
      name = name,
      quality = quality,
      count = count
    })
  end

  return true
end
```

- [ ] **Step 3: Call feedback filter when advancing steps**

In `start_next_internal_step`, after selecting the next `step`, call:

```lua
M.apply_feedback_filter(workshop_data, step)
```

This allows the output inserter to move intermediate products to the provider, and the feedback inserter to pull them back to the requester for the next step.

- [ ] **Step 4: Update e2e multi-step test**

After the first internal step (e.g., iron-plate) completes, simulate the output inserter moving iron-plate to the provider and the feedback inserter moving it back to the requester. Then assert the next step starts.

- [ ] **Step 5: Run tests**

Run: `busted spec`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add prototypes/entity.lua scripts/constants.lua scripts/companions.lua scripts/workshop.lua spec/e2e_spec.lua
git commit -m "feat(workshop): add feedback inserter for internal intermediate crafting"
```

---

### Task 5: Remove legacy Lua inventory teleportation helpers

**Files:**
- Modify: `scripts/workshop.lua`
- Test: `spec/workshop_spec.lua`

- [ ] **Step 1: Delete obsolete functions**

Remove:
- `M.move_requester_to_internal`
- `M.insert_internal_to_workshop`
- `M.collect_workshop_output_to_internal`
- `M.output_internal_inventory`
- Internal helper functions `internal_add`, `internal_remove`, `internal_count` (if no longer used)

Keep `assignment.internal_inventory` only if it is still used for tracking reserved construction output or returned items. Otherwise remove references to it.

- [ ] **Step 2: Update `clear_workshop_job`, `abandon_waiting_assignment`, and `reset_workshop_assignment`**

These no longer need to output an internal inventory. They should still clear requester filters and set the workshop recipe to nil.

- [ ] **Step 3: Update tests**

Remove or rewrite tests that rely on the removed helpers. Keep tests for:
- Clearing jobs
- Queue behavior
- Inserter filter application

- [ ] **Step 4: Run tests**

Run: `busted spec`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/workshop.lua spec/workshop_spec.lua
rm inserter-driven-workshop-plan.md
# do not remove the plan file; keep it as documentation
git commit -m "refactor(workshop): remove Lua inventory teleportation helpers"
```

---

### Task 6: Handle byproducts and returned empty barrels

**Files:**
- Modify: `scripts/workshop.lua`
- Test: `spec/e2e_spec.lua`

- [ ] **Step 1: Track non-target outputs**

When a step completes, the output inserter moves all products to the provider. For barrelled recipes, empty barrels are returned. These should be treated as available network supply, not as targets.

Add `assignment.returned_items` to track items produced by the step that are not the step target. When the assignment finishes, log or display them but do not reserve them for construction.

- [ ] **Step 2: Update barrelled recipe e2e test**

Create a test where a barrelled recipe is run. Assert:
- Target item lands in provider
- Empty barrels land in provider
- Workshop becomes idle

- [ ] **Step 3: Commit**

```bash
git add scripts/workshop.lua spec/e2e_spec.lua
git commit -m "feat(workshop): handle barrelled recipe byproducts via output inserter"
```

---

## Phase 2: Single Wireable Workshop Entity

### Task 7: Design the standalone workshop entity

**Files:**
- Modify: `prototypes/entity.lua`
- Modify: `scripts/registration.lua`

- [ ] **Step 1: Add a new prototype variant or replace the existing one**

Create `logistic-nexus-workshop-integrated` (or update the existing prototype) with:
- Built-in requester/provider logistic cells (if the API allows) **or** clearly marked input/output connection points for the player to wire chests.
- Circuit network read/write interface for demand signals.
- No companion buildings.

This task is exploratory; the exact API limitations should be checked against the Factorio 2.0 prototype docs.

- [ ] **Step 2: Document API findings**

Add a section to this plan or a separate `standalone-workshop-notes.md` explaining:
- Whether an assembling-machine can have logistic requester cells
- How circuit signals can set request filters
- How the player connects input/output belts

- [ ] **Step 3: Commit**

```bash
git add prototypes/entity.lua standalone-workshop-notes.md
# if notes file is created
git commit -m "docs: standalone workshop design notes"
```

---

### Task 8: Read network demand signals to set internal requests

**Files:**
- Modify: `scripts/workshop.lua`
- Modify: `scripts/brain.lua`

- [ ] **Step 1: Add `Workshop.read_network_demand_signals(workshop)`**

Read circuit/logistic signals from the workshop and return a map of `{name, quality} -> requested_count`.

- [ ] **Step 2: Use signals as an additional demand source in `Brain.process_brain`**

Merge signal demand with requester-point and construction demand before building shortages.

- [ ] **Step 3: Commit**

```bash
git add scripts/workshop.lua scripts/brain.lua
# no test yet; add one before committing
git commit -m "feat(brain): include workshop demand signals in shortage calculation"
```

---

## Testing Strategy

- Unit tests for inserter filter configuration.
- Unit tests for feedback filter logic.
- E2E tests for single-step, multi-step, and barrelled recipes using mocked inserter movement.
- Luacheck on every commit.
- Manual in-game test save for visual confirmation that inserters move items correctly.

---

## Migration Notes

- Existing saves will have orphan companion inserters if Phase 1 is deployed. `Registration.rebuild_workshops` must destroy old companions and recreate them with inserters.
- The `internal_inventory` field can be removed from `assignment` once Phase 1 is complete, unless it is repurposed for tracking returned items.
- The `status-blocked` locale string should be updated from "side space blocked" to a generic "blocked" message.

---

## Spec Coverage Check

| Requirement | Task |
|-------------|------|
| Use actual inserters instead of Lua teleportation | Task 1, 3, 4, 5 |
| Assembler auto-sets recipe | Existing `set_workshop_recipe`, unchanged |
| Inserter moves items from requester to assembler | Task 1 |
| Inserter moves output to provider | Task 1 |
| Inserter moves intermediates back to input | Task 4 |
| Transparent workshop activity | Inserter animation visible in-game |
| Future single-building direction | Task 7, 8 |
| Auto-set requests from network signals | Task 8 |
| Still requires wired inputs/outputs | Task 7 design |

---

*Plan saved to repo root as requested.*
