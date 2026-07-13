# Logistic Nexus TODO

Known limitations and potential future features.

## Open

### 3. Fixed crafting speed
The workshop has `crafting_speed = 1` with no upgrade path. Consider tiered
workshops or research-based speed upgrades.

### 10. No alerts when an item cannot be crafted
Blocked items are only visible through the entity status icon. Consider
flying-text alerts or console messages when a requested item is uncraftable.

### 11. No blueprint copy-paste support
The workshop prototype sets `allow_copy_paste = false`. Consider enabling
blueprint copy-paste, at least for circuit conditions.

### 12. No workshop upgrade tiers
Only one workshop entity exists and `next_upgrade = nil`. Consider faster or
MK2 workshop variants.

## Done

### 1. One final-product job per workshop at a time
Workshops now maintain a `job_queue` of up to `WORKSHOP_QUEUE_SIZE` final-product jobs.
The brain assigns jobs to any workshop with queue space, and when a job finishes draining
the next queued job starts immediately instead of waiting for the next assessment tick.

### 2. No module / beacon / effect support
The workshop prototype now has 4 module slots and allows all effects (consumption,
speed, productivity, pollution). Factorio handles speed/productivity/beacon bonuses
automatically for assembling-machine entities.

### 9. No production statistics or status GUI
Added `/logistic-nexus-gui` which opens a status panel showing workshop summary,
target shortages, active counts, blocked reasons, and per-workshop state/progress.

### 18. Better handling of script-enabled recipes
Fixed by clearing negative recipe-cache entries during each assessment, so
recipes enabled by scripts or mods after the initial scan are discovered.
