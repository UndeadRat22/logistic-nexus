# Bug Report: AG Mall 0.1.8 still doesn't recognize recipes unlocked after research

## Summary

The 0.1.8 fix for "recipe refresh after research unlocks" doesn't actually work. The `reset_force_recipe_effects` code path it added is never invoked when research completes, due to a missing `options` argument at the research-event call sites.

## Root Cause

In 0.1.8, `sync_barrelled_recipes(force, options)` only calls `reset_force_recipe_effects(force)` when `options.reset_force_effects` is truthy. That flag is passed correctly from `script.on_init` and `script.on_configuration_changed`, but the three research-event handlers don't pass it:

```lua
-- 0.1.8 as released (control.lua ~line 4047)
script.on_event(defines.events.on_research_finished, function(event)
  sync_barrelled_recipes(event.research and event.research.force)  -- ← no options
end)

if defines.events.on_research_reversed then
  script.on_event(defines.events.on_research_reversed, function(event)
    sync_barrelled_recipes(event.research and event.research.force)  -- ← no options
  end)
end

if defines.events.on_technology_effects_reset then
  script.on_event(defines.events.on_technology_effects_reset, function(event)
    sync_barrelled_recipes(event.force)  -- ← no options
  end)
end
```

Without the flag, `reset_force_recipe_effects(force)` is skipped, so `force.reset_recipes()` and `force.reset_technology_effects()` never run on research completion. The brain cache is invalidated and barrelled recipes are re-synced, but the underlying recipe prototypes stay in their pre-research `enabled = false` state. `recipe_can_make_item()` then rejects them on the next scheduling pass — same symptom as before.

## Fix

Pass `{reset_force_effects = true}` at all three research handlers:

```lua
script.on_event(defines.events.on_research_finished, function(event)
  sync_barrelled_recipes(event.research and event.research.force, {reset_force_effects = true})
end)

if defines.events.on_research_reversed then
  script.on_event(defines.events.on_research_reversed, function(event)
    sync_barrelled_recipes(event.research and event.research.force, {reset_force_effects = true})
  end)
end

if defines.events.on_technology_effects_reset then
  script.on_event(defines.events.on_technology_effects_reset, function(event)
    sync_barrelled_recipes(event.force, {reset_force_effects = true})
  end)
end
```

## Testing

1. Start a new map with the patched mod.
2. Place an AG Mall and request a starter item (e.g. transport belts) — should craft.
3. Research a technology that unlocks a new craftable item (e.g. Logistics → fast transport belt).
4. Request the newly unlocked item.
5. Confirm the mall schedules and crafts it.

## Files Changed

- `control.lua`
