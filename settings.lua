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
    type = "int-setting",
    name = "logistic-nexus-max-batches-per-job",
    setting_type = "runtime-global",
    default_value = 5,
    minimum_value = 1,
    maximum_value = 100,
    order = "b"
  }
})
