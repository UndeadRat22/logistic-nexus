# Logistic Nexus TODO

Known limitations and potential future features.

## Open

## Done

### 1. One final-product job per workshop at a time
Workshops now maintain a `job_queue` of up to `WORKSHOP_QUEUE_SIZE` final-product jobs.
The brain assigns jobs to any workshop with queue space, and when a job finishes draining
the next queued job starts immediately instead of waiting for the next assessment tick.

### 2. No module / beacon / effect support
The workshop prototype now has 4 module slots and allows all effects (consumption,
speed, productivity, pollution). Factorio handles speed/productivity/beacon bonuses
automatically for assembling-machine entities.

### 3. Fixed crafting speed
Addressed by the MK2 workshop tier (see item #12).

### 10. No alerts when an item cannot be crafted
Added flying-text alerts for blocked items. When a shortage is uncraftable or
a plan is blocked, `Brain.process_brain` triggers `Alerts.alert_blocked_item`,
which creates a red flying-text label at a workshop and respects a per-item
cooldown to avoid spam.

### 11. No blueprint copy-paste support
Both workshop tiers now set `allow_copy_paste = true`, so blueprints include
the workshop and preserve circuit-wire connections. Companion entities remain
`not-blueprintable` and are recreated automatically when the workshop is built.

### 12. No workshop upgrade tiers
Added `logistic-nexus-workshop-mk2` with `crafting_speed = 2`, 6 module slots,
and a technology unlock. The base workshop now has `next_upgrade` pointing to
MK2, and all runtime checks use `WORKSHOP_NAMES` so both tiers are registered,
mined, rebuilt, and prioritized.

### 9. No production statistics or status GUI
Added `/logistic-nexus-gui` which opens a status panel showing workshop summary,
target shortages, active counts, blocked reasons, and per-workshop state/progress.

### 18. Better handling of script-enabled recipes
Fixed by clearing negative recipe-cache entries during each assessment, so
recipes enabled by scripts or mods after the initial scan are discovered.
