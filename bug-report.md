# Bug Report: AG Mall does not recognize recipes unlocked after the mod is installed

## Summary

When AG Mall is installed at the start of a playthrough, it can craft items whose recipes are enabled by default (e.g. iron gear wheels, iron sticks, transport belts). However, recipes that are unlocked by researching technologies later in the game are never picked up by the mall. If the mod is installed later, after those technologies have already been researched, the same recipes work correctly.

## Reproduction Steps

1. Start a new game with AG Mall installed.
2. Place an AG Mall inside a logistic network and provide raw materials.
3. Create demand for a starting item (e.g. transport belts) — the mall crafts it.
4. Research a technology that unlocks a new craftable item (e.g. Logistics → fast transport belt, or Automation 2 → assembling machine 2).
5. Create demand for the newly-unlocked item via a requester chest, personal logistics, or construction ghost.

**Expected:** The AG Mall detects the shortage and schedules the item for crafting.  
**Actual:** The mall acts as if no craftable recipe exists and ignores the request.

## Root Cause

The issue is in `control.lua`, in the function `sync_barrelled_recipes()`.

That function has two jobs related to recipe availability:

1. Reload recipe prototypes and reapply researched technology effects.
2. Clear the mall’s per-network recipe cache (`brain.recipe_choices`).

Originally it was doing the first job inside a guard that only ran once per force:

```lua
if not storage.barrelled_recipe_effects_reset[force.name] then
  force.reset_technology_effects()
  force.reset_recipes()
  storage.barrelled_recipe_effects_reset[force.name] = true
end
```

After that first run, every subsequent `on_research_finished` only cleared the cache and enabled barrelled recipes. But clearing the cache is not enough: the newly-unlocked recipe may still be in a disabled/unloaded state in `force.recipes`, so `recipe_can_make_item()` rejects it on the next scheduling pass.

In addition, the reset order was backwards: `reset_technology_effects()` was called **before** `reset_recipes()`. The correct order is to reload prototypes first, then reapply researched tech effects, so that unlocked recipes end up enabled.

## Fix

Apply the following changes to `control.lua`:

### 1. Remove the one-shot guard from `sync_barrelled_recipes()`

The prototype/tech-effect reset must run on every research event, not just once.

### 2. Swap the reset order

Call `force.reset_recipes()` first, then `force.reset_technology_effects()`.

### 3. Remove the now-unused `barrelled_recipe_effects_reset` storage field

It is no longer referenced and would otherwise become dead data in existing saves.

## Diff

```diff
--- a/control.lua
+++ b/control.lua
@@ -59,9 +59,6 @@ local function init_storage()
   if type(storage.brains) ~= "table" then
     storage.brains = {}
   end
-  if type(storage.barrelled_recipe_effects_reset) ~= "table" then
-    storage.barrelled_recipe_effects_reset = {}
-  end
   if type(storage.construction_scans) ~= "table" then
     storage.construction_scans = {}
   end
@@ -3885,18 +3882,16 @@ end
 
 function sync_barrelled_recipes()
   storage.last_barrelled_recipe_sync = game.tick
-  storage.barrelled_recipe_effects_reset = storage.barrelled_recipe_effects_reset or {}
 
   for _, force in pairs(game.forces) do
-    if not storage.barrelled_recipe_effects_reset[force.name] then
-      pcall(function()
-        force.reset_technology_effects()
-      end)
-      pcall(function()
-        force.reset_recipes()
-      end)
-      storage.barrelled_recipe_effects_reset[force.name] = true
-    end
+    -- Reload recipe prototypes from data first, then reapply researched tech effects.
+    -- Doing this on every research event guarantees that newly-unlocked recipes
+    -- are actually available to the mall instead of getting stuck in a disabled state.
+    pcall(function()
+      force.reset_recipes()
+    end)
+    pcall(function()
+      force.reset_technology_effects()
+    end)
 
     for recipe_name, recipe in pairs(force.recipes) do
       if type(recipe_name) == "string"
```

## Impact / Trade-offs

- `force.reset_recipes()` and `force.reset_technology_effects()` now run on every `on_research_finished` event. Research is infrequent, so the performance impact should be negligible in normal play.
- These calls are wrapped in `pcall`, so a failure in one force does not break processing for others.
- The fix makes newly-unlocked recipes available immediately, without requiring a mod reinstall or a save/load cycle.

## Testing Suggestion

1. Start a new map with the patched mod.
2. Place an AG Mall and request a starter item (e.g. transport belts) — should craft.
3. Research a technology that unlocks a new craftable item (e.g. Logistics for fast inserters / fast belts).
4. Request the newly unlocked item.
5. Confirm the mall schedules and crafts it.

## Files Changed

- `control.lua`
