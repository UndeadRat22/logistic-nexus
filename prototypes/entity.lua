local workshop = table.deepcopy(data.raw["assembling-machine"]["assembling-machine-3"])
local map_display = table.deepcopy(data.raw["assembling-machine"]["assembling-machine-1"])
local world_display = table.deepcopy(data.raw["assembling-machine"]["assembling-machine-1"])
local requester = table.deepcopy(data.raw["logistic-container"]["requester-chest"])
local provider = table.deepcopy(data.raw["logistic-container"]["active-provider-chest"])
local input_inserter = table.deepcopy(data.raw["inserter"]["fast-inserter"])
local output_inserter = table.deepcopy(data.raw["inserter"]["fast-inserter"])

workshop.name = "logistic-nexus-workshop"
workshop.localised_name = {"entity-name.logistic-nexus-workshop"}
workshop.localised_description = {"entity-description.logistic-nexus-workshop"}
workshop.icon = "__logistic-nexus__/graphics/icons/logistic-nexus-workshop.png"
workshop.icon_size = 64
workshop.minable = {
  mining_time = 0.3,
  result = "logistic-nexus-workshop"
}
workshop.fast_replaceable_group = "logistic-nexus-workshop"
workshop.next_upgrade = nil
workshop.allow_copy_paste = true
workshop.crafting_speed = 1
workshop.module_slots = 4
workshop.allowed_effects = {"consumption", "speed", "productivity", "pollution"}
workshop.energy_usage = "750kW"
workshop.fluid_boxes = nil
workshop.fluid_boxes_off_when_no_fluid_recipe = nil
workshop.show_recipe_icon = false
workshop.show_recipe_icon_on_map = false
workshop.circuit_connector = circuit_connector_definitions.create_vector(
  universal_connector_template,
  {
    {variation = 18, main_offset = util.by_pixel(8, 41), shadow_offset = util.by_pixel(19, 47), show_shadow = true},
    {variation = 18, main_offset = util.by_pixel(8, 41), shadow_offset = util.by_pixel(19, 47), show_shadow = true},
    {variation = 18, main_offset = util.by_pixel(8, 41), shadow_offset = util.by_pixel(19, 47), show_shadow = true},
    {variation = 18, main_offset = util.by_pixel(8, 41), shadow_offset = util.by_pixel(19, 47), show_shadow = true}
  }
)
workshop.graphics_set = table.deepcopy(data.raw["assembling-machine"]["assembling-machine-1"].graphics_set)
workshop.graphics_set.animation.layers[1].filename =
  "__logistic-nexus__/graphics/entity/logistic-nexus/logistic-nexus.png"
workshop.graphics_set.animation.layers[1].width = 278
workshop.graphics_set.animation.layers[1].height = 290
workshop.graphics_set.animation.layers[1].shift = util.by_pixel(0, 2)
workshop.graphics_set.animation.layers[2].filename =
  "__logistic-nexus__/graphics/entity/logistic-nexus/logistic-nexus-shadow.png"
workshop.graphics_set.animation.layers[2].width = 264
workshop.graphics_set.animation.layers[2].height = 247
workshop.graphics_set.animation.layers[2].frame_count = 32
workshop.graphics_set.animation.layers[2].line_length = 8
workshop.graphics_set.animation.layers[2].repeat_count = nil
workshop.graphics_set.animation.layers[2].shift = util.by_pixel(8.5, 5)

-- The entity owns a square 4x4 area. Its 3x3 artwork and selection area are
-- shifted into the lower-left, leaving the top row and right column reserved.
workshop.tile_width = 4
workshop.tile_height = 4
workshop.collision_box = {{-1.99, -1.99}, {1.99, 1.99}}
workshop.selection_box = {{-2, -1}, {1, 2}}
workshop.flags = workshop.flags or {}
table.insert(workshop.flags, "hide-alt-info")
-- Select over the internal companion chests so the workshop GUI opens when clicked.
workshop.selection_priority = 51

local workshop_mk2 = table.deepcopy(workshop)
workshop_mk2.name = "logistic-nexus-workshop-mk2"
workshop_mk2.localised_name = {"entity-name.logistic-nexus-workshop-mk2"}
workshop_mk2.localised_description = {"entity-description.logistic-nexus-workshop-mk2"}
workshop_mk2.icon = "__logistic-nexus__/graphics/icons/logistic-nexus-workshop.png"
workshop_mk2.minable = {
  mining_time = 0.3,
  result = "logistic-nexus-workshop-mk2"
}
workshop_mk2.fast_replaceable_group = "logistic-nexus-workshop"
workshop_mk2.next_upgrade = nil
workshop_mk2.allow_copy_paste = true
workshop_mk2.crafting_speed = 2
workshop_mk2.module_slots = 6
workshop_mk2.energy_usage = "1500kW"
workshop_mk2.selection_priority = 51

workshop.next_upgrade = "logistic-nexus-workshop-mk2"

map_display.name = "logistic-nexus-map-display"
map_display.localised_name = {"entity-name.logistic-nexus-workshop"}
map_display.minable = nil
map_display.fast_replaceable_group = nil
map_display.next_upgrade = nil
map_display.allow_copy_paste = false
map_display.hidden_in_factoriopedia = true
map_display.selectable_in_game = false
map_display.bottleneck_ignore = true
map_display.collision_mask = {layers = {}}
map_display.show_recipe_icon = false
map_display.show_recipe_icon_on_map = true
map_display.draw_entity_info_icon_background = true
map_display.icon_draw_specification = {
  shift = {0.45, -1.3},
  scale = 0.75
}
map_display.graphics_set = {
  animation = {
    filename = "__core__/graphics/empty.png",
    width = 1,
    height = 1
  }
}
map_display.circuit_connector = nil
map_display.circuit_wire_max_distance = nil
map_display.fluid_boxes = nil
map_display.fluid_boxes_off_when_no_fluid_recipe = nil
map_display.energy_source = {type = "void"}
map_display.energy_usage = "1W"
map_display.flags = map_display.flags or {}
table.insert(map_display.flags, "not-blueprintable")
table.insert(map_display.flags, "not-deconstructable")
table.insert(map_display.flags, "not-flammable")
table.insert(map_display.flags, "not-repairable")

world_display.name = "logistic-nexus-world-display"
world_display.localised_name = {"entity-name.logistic-nexus-workshop"}
world_display.minable = nil
world_display.fast_replaceable_group = nil
world_display.next_upgrade = nil
world_display.allow_copy_paste = false
world_display.hidden_in_factoriopedia = true
world_display.selectable_in_game = false
world_display.bottleneck_ignore = true
world_display.collision_mask = {layers = {}}
world_display.collision_box = {{0, 0}, {0, 0}}
world_display.selection_box = {{0, 0}, {0, 0}}
world_display.show_recipe_icon = true
world_display.show_recipe_icon_on_map = false
world_display.draw_entity_info_icon_background = true
world_display.icon_draw_specification = {
  shift = {0.45, -1.3},
  scale = 0.75
}
world_display.graphics_set = table.deepcopy(map_display.graphics_set)
world_display.circuit_connector = nil
world_display.circuit_wire_max_distance = nil
world_display.fluid_boxes = nil
world_display.fluid_boxes_off_when_no_fluid_recipe = nil
world_display.energy_source = {type = "void"}
world_display.energy_usage = "1W"
world_display.flags = table.deepcopy(map_display.flags)

requester.name = "logistic-nexus-requester"
requester.localised_name = {"entity-name.logistic-nexus-requester"}
requester.localised_description = {"entity-description.logistic-nexus-requester"}
requester.minable = nil
requester.hidden_in_factoriopedia = true
requester.flags = {
  "placeable-player",
  "player-creation",
  "not-blueprintable",
  "not-deconstructable"
}
requester.collision_mask = {layers = {}}

provider.name = "logistic-nexus-provider"
provider.localised_name = {"entity-name.logistic-nexus-provider"}
provider.localised_description = {"entity-description.logistic-nexus-provider"}
provider.minable = nil
provider.hidden_in_factoriopedia = true
provider.flags = {
  "placeable-player",
  "player-creation",
  "not-blueprintable",
  "not-deconstructable"
}
provider.collision_mask = {layers = {}}

input_inserter.name = "logistic-nexus-input-inserter"
input_inserter.localised_name = {"entity-name.logistic-nexus-input-inserter"}
input_inserter.localised_description = {"entity-description.logistic-nexus-input-inserter"}
input_inserter.minable = nil
input_inserter.next_upgrade = nil
input_inserter.hidden_in_factoriopedia = true
input_inserter.selectable_in_game = false
input_inserter.allow_copy_paste = false
input_inserter.flags = {
  "placeable-player",
  "player-creation",
  "not-blueprintable",
  "not-deconstructable",
  "hide-alt-info"
}

output_inserter.name = "logistic-nexus-output-inserter"
output_inserter.localised_name = {"entity-name.logistic-nexus-output-inserter"}
output_inserter.localised_description = {"entity-description.logistic-nexus-output-inserter"}
output_inserter.minable = nil
output_inserter.next_upgrade = nil
output_inserter.hidden_in_factoriopedia = true
output_inserter.selectable_in_game = false
output_inserter.allow_copy_paste = false
output_inserter.flags = {
  "placeable-player",
  "player-creation",
  "not-blueprintable",
  "not-deconstructable",
  "hide-alt-info"
}

data:extend({
  workshop,
  workshop_mk2,
  map_display,
  world_display,
  requester,
  provider,
  input_inserter,
  output_inserter
})
