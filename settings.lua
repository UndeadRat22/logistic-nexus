data:extend({
  {
    type = "string-setting",
    name = "logistic-nexus-excluded-categories",
    setting_type = "startup",
    default_value = "",
    allow_blank = true,
    auto_trim = true,
    order = "a"
  },
  {
    type = "bool-setting",
    name = "logistic-nexus-enable-modules",
    setting_type = "startup",
    default_value = false,
    order = "b"
  },
  {
    type = "int-setting",
    name = "logistic-nexus-max-batches-per-job",
    setting_type = "runtime-global",
    default_value = 5,
    minimum_value = 1,
    maximum_value = 100,
    order = "c"
  },
  {
    type = "bool-setting",
    name = "logistic-nexus-debug-logging",
    setting_type = "runtime-global",
    default_value = false,
    order = "d"
  }
})
