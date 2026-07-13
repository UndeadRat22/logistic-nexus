# Bulk Crafting Design

## Goal
Allow Logistic Nexus workshops to craft up to a configurable number of recipe batches in a single job, instead of always crafting one batch at a time.

## Motivation
Currently the scheduler assigns one recipe batch per job. For high-volume requests (e.g. 50 transport belts) this means workshops repeatedly take small bites, causing more scheduler cycles and slower response. A global batch-size setting lets players tune throughput without per-item configuration.

## Non-goals
- Per-item batch sizes.
- Per-workshop or circuit-controlled batch sizes (may follow later).
- Changing how internal intermediate crafting is planned beyond scaling the root recipe.

## Design

### 1. Mod setting
Add a runtime-global integer setting in `settings.lua`:

| Field | Value |
|-------|-------|
| name | `logistic-nexus-max-batches-per-job` |
| type | `int-setting` |
| setting_type | `runtime-global` |
| default_value | 5 |
| minimum_value | 1 |
| maximum_value | 100 |
| order | "b" |

Add localized name and description in `locale/en/logistic-nexus.cfg`.

### 2. Planner changes

#### New parameter
`Planner.build_internal_craft_plan(workshop, network, target_name, quality, brain, options)` gains an `options.max_batches` value (default 1 for backward compatibility).

#### Algorithm
1. **Check craftability of a single batch.** Run the existing planner logic with `batch_count = 1`. If this fails, return `nil, blocked` immediately — preserving today’s behavior for uncraftable items.
2. **Binary search for largest feasible batch count.** Search the range `[1, max_batches]`:
   - `low = 1`, `high = max_batches`, `best_plan = nil`.
   - While `low <= high`:
     - `mid = floor((low + high) / 2)`.
     - Run the planner logic with `batch_count = mid`.
     - If feasible: `best_plan = plan`, `low = mid + 1`.
     - Else: `high = mid - 1`.
3. Return `best_plan`.

#### Scaling a plan for `batch_count`
- Root ingredients: use `Recipes.aggregate_recipe_ingredients(recipe, batch_count, quality)`.
- Root output amount: `product_amount * batch_count`.
- Root recipe step: insert once with scaled output amount.
- Children: the existing `plan_item`/`append_recipe_steps` logic already scales child craft counts from the requested amount, so deeper intermediates naturally adjust.

#### Refactoring
Extract the core plan-building body into a local helper `build_plan_for_batches(batch_count)` so it can be reused for the feasibility check and each binary-search step without duplicating code.

### 3. Brain/scheduler integration

- In `Brain.build_scheduler_candidates`, when a candidate is found, compute `product_amount` as today.
- In `Brain.choose_independent_job`, read `settings.global["logistic-nexus-max-batches-per-job"].value` once per call (or once per assess cycle) and pass it through `Planner.build_candidate_plan` in `options.max_batches`.
- `Planner.build_candidate_plan` forwards `max_batches` to `build_internal_craft_plan`.
- The returned plan’s `target_output_amount` will be `product_amount * chosen_batch_count`.

### 4. Workshop integration

`Workshop.start_job_now` already uses:
```lua
local expected_output = job.target_output_amount or job.product_amount or 1
```
No change is required: the scaled output amount flows through `assignment.expected_output` and `workshop_data.current_product_amount`, so the workshop keeps the recipe active until the full batch is produced.

### 5. Supply budget

`Planner.apply_supply_use` is called once per job using the chosen plan’s `network_used`. Because the binary search picks the largest feasible batch, the budget accurately reflects consumed network resources.

### 6. Edge cases and safeguards

- If `max_batches = 1`, behavior is byte-identical to current single-batch crafting.
- If even one batch is infeasible, the candidate is skipped with the same blocked reason as today.
- Construction reservations are per-item and per-quality; scaling output amount naturally reserves the larger batch count.
- The job queue size (`WORKSHOP_QUEUE_SIZE = 3`) is unchanged because a single bulk job replaces multiple small jobs.

## Testing

1. **Planner unit tests** (`spec/planner_spec.lua`):
   - Mock recipe with fixed product amount and available network supply.
   - Verify `max_batches = 1` matches current single-batch output.
   - Verify with enough supply, the planner picks `max_batches`.
   - Verify with limited supply, binary search returns the largest feasible batch count.
   - Verify uncraftable item returns blocked after the single-batch feasibility check.

2. **Brain integration test** (`spec/brain_spec.lua`):
   - Stub the new setting and verify `choose_independent_job` passes the configured value into the planner.

3. **Setting registration test** (`spec/data_stage_util_spec.lua` or new test):
   - Verify the setting is defined with correct default, min, max, and type.

## Files to modify

- `settings.lua`
- `locale/en/logistic-nexus.cfg`
- `scripts/planner.lua`
- `scripts/brain.lua`
- `spec/planner_spec.lua`
- `spec/brain_spec.lua`

## Future work

- Per-item batch multipliers.
- Circuit-controlled batch size per workshop group.
