# Plan: Split control.lua into Modules + Add Unit Tests

## Context

`control.lua` is a 4279-line monolith containing all runtime logic for the AG Mall Factorio mod. It has clear section comments (STORAGE, STATUS, COMPANION ENTITIES, PLANNER, WORKSHOP REGISTRATION, EVENTS) but zero module boundaries — everything is local functions in one file, with forward declarations bridging circular dependencies.

**Constraint: No behavioural changes.** This is a pure refactor + test scaffolding.

## Problem Areas

1. **Single giga-file** — 4279 lines, ~15 logical concerns, no `require` boundaries.
2. **Forward-declaration coupling** — 5 forward-declared locals (`sync_barrelled_recipes`, `get_cached_supply_count`, `mark_network_schedule_dirty`, `ingredient_count`, `preflight_replans_remaining`) bridge circular deps between sections.
3. **No tests** — Zero test infrastructure. Pure functions are buried inside the monolith with no way to require them independently.
4. **Factorio API coupling** — Functions freely use `storage`, `defines`, `game`, `script`, `commands`, `rendering`, `pcall`. Pure functions (item keys, recipe math, sorting) are mixed with API-coupled code.

## Strategy

### Module split

Create a `scripts/` directory and split into modules by logical concern. Factorio's `require()` works at runtime — each module returns a table of exported functions. Forward-declared functions become explicit module dependencies passed via the requiring module.

**New file structure:**
```
control.lua                    # Entry point: requires modules, registers events, ~80 lines
scripts/
  constants.lua                # All name/interval/limit constants
  util.lua                     # Pure helpers: quality_name, item_key, split_item_key, item_id, ingredient_count, fixed_*_amount, add_count, counts_to_ingredients, copy_counts, stack_definition, position_key
  status.lua                   # set_*_status, set_custom_status, goal sprite management
  storage.lua                  # init_storage, get_construction_reservations, brain storage helpers
  companions.lua               # companion_layout, create/get/destroy companions, requester configuration
  construction.lua            # construction scanning, reservations, ghost requests
  recipes.lua                  # recipe validation, finding, caching
  planner.lua                  # build_internal_craft_plan, decorate_plan, build_candidate_plan
  workshop.lua                 # workshop assignment lifecycle, internal inventory, worker ticking
  brain.lua                    # brain management, scheduling, assess_all_workshops
  registration.lua             # register/unregister workshops, debug commands, rebuild, recipe sync
  events.lua                   # All script.on_event handlers, commands.add_command, on_init, on_configuration_changed
```

### Dependency wiring

Instead of forward declarations, each module `require`s its dependencies and receives them as module-level locals. Circular dependencies (e.g., `workshop` needs `planner` needs `recipes` needs `util`) are broken by ensuring the dependency graph is acyclic:

```
constants          (no deps)
util               (deps: constants)
storage            (deps: constants)
status             (deps: constants)
companions         (deps: constants, util, status)
recipes            (deps: constants, util)
construction       (deps: constants, util, storage)
planner            (deps: constants, util, recipes)
workshop           (deps: constants, util, companions, status, recipes, planner)
brain              (deps: constants, util, storage, construction, workshop, recipes, planner)
registration       (deps: all above)
events             (deps: all above)
control.lua        (deps: events, registration)
```

State that is currently shared via file-level locals (`preflight_replans_remaining`) becomes a field on a shared state table or brain object.

### Pure function extraction for testability

Many functions have no Factorio API dependency and are pure logic. These are the primary test targets:

| Function | Current location | Test category |
|---|---|---|
| `quality_name` | inline | util |
| `item_key`, `split_item_key` | inline | util |
| `item_id` | inline | util |
| `fixed_product_amount`, `fixed_ingredient_amount` | inline | util |
| `ingredient_count` | inline | util |
| `add_count`, `counts_to_ingredients` | inline | util |
| `copy_counts` | inline | util |
| `stack_definition` | inline | util |
| `position_key` | inline | util |
| `shortage_sort` | inline | brain/util |
| `candidate_choice_sort` | inline | brain/util |
| `construction_reservation_key` | inline | construction |
| `construction_scan_key` | inline | construction |
| `brain_key` | inline | brain |
| `recipe_is_available_to_mall` | inline | recipes |
| `recipe_product_amount` | inline | recipes |
| `recipe_item_ingredients` | inline | recipes |
| `aggregate_recipe_ingredients` | inline | recipes |
| `recipe_outputs` | inline | recipes |

These are moved to `util.lua` / `recipes.lua` and tested without any Factorio mocks.

### Test infrastructure

- **Runner:** `busted` (installed, works with Lua 5.5)
- **Location:** `spec/` directory (busted convention)
- **Mock strategy:** For functions that touch Factorio APIs (`storage`, `defines`, `game`), create a minimal mock `factorio` module in `spec/helpers.lua` that stubs `defines`, `storage`, `game`, `script`, `commands`. This is only needed for integration-style tests of higher-level modules.
- **Primary focus:** Unit-test the pure functions thoroughly. Add a few smoke tests for module loading (each module can be `require`d without error when Factorio globals are mocked).

### Verification

1. After the split, `control.lua` should be ~80 lines (just requires + event registration).
2. Each module should be independently `require`-able in busted with appropriate mocks.
3. All pure functions have test coverage.
4. `busted` runs green.
5. Diff against original `control.lua` confirms no logic changes (function bodies are byte-identical, just moved).

## Execution Steps

1. **Create `scripts/constants.lua`** — Extract all constants.
2. **Create `scripts/util.lua`** — Extract pure helpers. This is the testable core.
3. **Create `scripts/storage.lua`** — Extract storage init/access.
4. **Create `scripts/status.lua`** — Extract status + sprite functions.
5. **Create `scripts/recipes.lua`** — Extract recipe validation/finding/caching.
6. **Create `scripts/companions.lua`** — Extract companion entity management.
7. **Create `scripts/construction.lua`** — Extract construction scanning/reservations.
8. **Create `scripts/planner.lua`** — Extract craft plan building.
9. **Create `scripts/workshop.lua`** — Extract workshop assignment/worker ticking.
10. **Create `scripts/brain.lua`** — Extract brain management/scheduling.
11. **Create `scripts/registration.lua`** — Extract workshop registration/debug/rebuild.
12. **Create `scripts/events.lua`** — Extract event handlers.
13. **Rewrite `control.lua`** — Thin entry point requiring `events`.
14. **Create `spec/helpers.lua`** — Factorio API mocks.
15. **Create `spec/util_spec.lua`** — Tests for pure util functions.
16. **Create `spec/recipes_spec.lua`** — Tests for pure recipe functions.
17. **Create `spec/construction_spec.lua`** — Tests for pure construction functions.
18. **Create `spec/brain_spec.lua`** — Tests for sort functions and brain key helpers.
19. **Run `busted`** — Verify all tests pass.
20. **Verify module loading** — Confirm every module loads without error under mocked Factorio globals.
