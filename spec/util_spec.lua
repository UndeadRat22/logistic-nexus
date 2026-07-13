local helpers = require("spec.helpers")

helpers.install_globals()
local Util = require("scripts.util")

describe("util", function()
  describe("quality_name", function()
    it("returns string quality as-is", function()
      assert.are.equal("normal", Util.quality_name("normal"))
      assert.are.equal("legendary", Util.quality_name("legendary"))
    end)

    it("extracts .name from quality object", function()
      assert.are.equal("uncommon", Util.quality_name({name = "uncommon"}))
    end)

    it("defaults to normal when nil", function()
      assert.are.equal("normal", Util.quality_name(nil))
    end)

    it("defaults to normal when no .name field", function()
      assert.are.equal("normal", Util.quality_name({}))
    end)
  end)

  describe("item_key", function()
    it("combines name and quality with pipe", function()
      assert.are.equal("iron-plate|normal", Util.item_key("iron-plate", "normal"))
      assert.are.equal("iron-plate|legendary", Util.item_key("iron-plate", "legendary"))
    end)

    it("handles quality object", function()
      assert.are.equal("copper-plate|epic", Util.item_key("copper-plate", {name = "epic"}))
    end)

    it("defaults quality to normal", function()
      assert.are.equal("steel-plate|normal", Util.item_key("steel-plate", nil))
    end)
  end)

  describe("split_item_key", function()
    it("splits name and quality", function()
      local name, quality = Util.split_item_key("iron-plate|normal")
      assert.are.equal("iron-plate", name)
      assert.are.equal("normal", quality)
    end)

    it("splits compound name with pipe", function()
      local name, quality = Util.split_item_key("ag-mall-barrelled-water|legendary")
      assert.are.equal("ag-mall-barrelled-water", name)
      assert.are.equal("legendary", quality)
    end)

    it("returns key as name when no pipe", function()
      local name, quality = Util.split_item_key("no-pipe-here")
      assert.are.equal("no-pipe-here", name)
      assert.are.equal("normal", quality)
    end)
  end)

  describe("item_id", function()
    it("returns plain name for normal quality", function()
      assert.are.equal("iron-plate", Util.item_id("iron-plate", "normal"))
      assert.are.equal("iron-plate", Util.item_id("iron-plate", nil))
    end)

    it("returns table with quality for non-normal", function()
      local id = Util.item_id("iron-plate", "legendary")
      assert.are.same({name = "iron-plate", quality = "legendary"}, id)
    end)

    it("handles quality object", function()
      local id = Util.item_id("iron-plate", {name = "epic"})
      assert.are.same({name = "iron-plate", quality = "epic"}, id)
    end)
  end)

  describe("fixed_product_amount", function()
    it("returns amount when positive", function()
      assert.are.equal(5, Util.fixed_product_amount({amount = 5}))
    end)

    it("returns nil when amount is zero", function()
      assert.is_nil(Util.fixed_product_amount({amount = 0}))
    end)

    it("returns nil when amount is nil", function()
      assert.is_nil(Util.fixed_product_amount({}))
    end)

    it("returns nil when amount is negative", function()
      assert.is_nil(Util.fixed_product_amount({amount = -1}))
    end)

    it("returns nil when probability is less than 1", function()
      assert.is_nil(Util.fixed_product_amount({amount = 5, probability = 0.5}))
    end)

    it("returns amount when probability is guaranteed", function()
      assert.are.equal(5, Util.fixed_product_amount({amount = 5, probability = 1}))
    end)
  end)

  describe("fixed_ingredient_amount", function()
    it("returns amount when valid", function()
      assert.are.equal(3, Util.fixed_ingredient_amount({amount = 3, type = "item"}))
    end)

    it("returns nil when probability is less than 1", function()
      assert.is_nil(Util.fixed_ingredient_amount({amount = 3, probability = 0.5}))
    end)

    it("returns amount when probability is guaranteed", function()
      assert.are.equal(3, Util.fixed_ingredient_amount({amount = 3, probability = 1}))
    end)

    it("returns nil when amount_min is set", function()
      assert.is_nil(Util.fixed_ingredient_amount({amount = 3, amount_min = 1}))
    end)

    it("returns nil when amount_max is set", function()
      assert.is_nil(Util.fixed_ingredient_amount({amount = 3, amount_max = 5}))
    end)

    it("returns nil when amount is zero", function()
      assert.is_nil(Util.fixed_ingredient_amount({amount = 0}))
    end)

    it("returns nil when ingredient is nil", function()
      assert.is_nil(Util.fixed_ingredient_amount(nil))
    end)
  end)

  describe("ingredient_count", function()
    it("ceils the fixed amount", function()
      assert.are.equal(3, Util.ingredient_count({amount = 3}))
      assert.are.equal(4, Util.ingredient_count({amount = 3.2}))
      assert.are.equal(3, Util.ingredient_count({amount = 2.1}))
    end)

    it("returns nil when amount is not fixed", function()
      assert.is_nil(Util.ingredient_count({amount = 3, probability = 0.5}))
      assert.is_nil(Util.ingredient_count({}))
    end)
  end)

  describe("add_count", function()
    it("adds to counts table", function()
      local counts = {}
      Util.add_count(counts, "iron", 5, "normal")
      assert.are.equal(5, counts["iron|normal"])
    end)

    it("accumulates counts", function()
      local counts = {}
      Util.add_count(counts, "iron", 5, "normal")
      Util.add_count(counts, "iron", 3, "normal")
      assert.are.equal(8, counts["iron|normal"])
    end)

    it("ignores zero amount", function()
      local counts = {}
      Util.add_count(counts, "iron", 0, "normal")
      assert.is_nil(counts["iron|normal"])
    end)

    it("ignores nil name", function()
      local counts = {}
      Util.add_count(counts, nil, 5, "normal")
      assert.are.same({}, counts)
    end)

    it("ignores negative amount", function()
      local counts = {}
      Util.add_count(counts, "iron", -5, "normal")
      assert.is_nil(counts["iron|normal"])
    end)
  end)

  describe("counts_to_ingredients", function()
    it("converts counts to sorted ingredient list", function()
      local counts = {
        ["copper|normal"] = 10,
        ["iron|normal"] = 5
      }
      local result = Util.counts_to_ingredients(counts)
      assert.are.equal("copper", result[1].name)
      assert.are.equal(10, result[1].amount)
      assert.are.equal("iron", result[2].name)
      assert.are.equal(5, result[2].amount)
    end)

    it("handles nil counts", function()
      local result = Util.counts_to_ingredients(nil)
      assert.are.same({}, result)
    end)

    it("skips zero amounts", function()
      local counts = {["iron|normal"] = 0}
      local result = Util.counts_to_ingredients(counts)
      assert.are.equal(0, #result)
    end)

    it("sorts by name then quality", function()
      local counts = {
        ["iron|legendary"] = 2,
        ["iron|normal"] = 5,
        ["copper|normal"] = 3
      }
      local result = Util.counts_to_ingredients(counts)
      assert.are.equal("copper", result[1].name)
      assert.are.equal("iron", result[2].name)
      assert.are.equal("legendary", result[2].quality)
      assert.are.equal("iron", result[3].name)
      assert.are.equal("normal", result[3].quality)
    end)
  end)

  describe("copy_counts", function()
    it("creates a shallow copy", function()
      local original = {a = 1, b = 2}
      local copy = Util.copy_counts(original)
      assert.are.same({a = 1, b = 2}, copy)
      copy.a = 99
      assert.are.equal(1, original.a)
    end)

    it("handles nil input", function()
      assert.are.same({}, Util.copy_counts(nil))
    end)
  end)

  describe("stack_definition", function()
    it("returns stack without quality for normal", function()
      local stack = Util.stack_definition("iron-plate", 50, "normal")
      assert.are.same({name = "iron-plate", count = 50}, stack)
    end)

    it("includes quality for non-normal", function()
      local stack = Util.stack_definition("iron-plate", 50, "legendary")
      assert.are.same({name = "iron-plate", count = 50, quality = "legendary"}, stack)
    end)

    it("handles quality object", function()
      local stack = Util.stack_definition("iron-plate", 50, {name = "epic"})
      assert.are.same({name = "iron-plate", count = 50, quality = "epic"}, stack)
    end)
  end)

  describe("position_key", function()
    it("formats position as x,y string", function()
      assert.are.equal("1.5,2.5", Util.position_key({x = 1.5, y = 2.5}))
      assert.are.equal("0,0", Util.position_key({x = 0, y = 0}))
    end)
  end)

  describe("shortage_sort", function()
    it("sorts by priority descending", function()
      local items = {
        {name = "a", priority = 2, missing = 10},
        {name = "b", priority = 4, missing = 5},
        {name = "c", priority = 3, missing = 7}
      }
      table.sort(items, Util.shortage_sort)
      assert.are.equal("b", items[1].name)
      assert.are.equal("c", items[2].name)
      assert.are.equal("a", items[3].name)
    end)

    it("sorts by missing descending when priority equal", function()
      local items = {
        {name = "a", priority = 2, missing = 5},
        {name = "b", priority = 2, missing = 10},
        {name = "c", priority = 2, missing = 7}
      }
      table.sort(items, Util.shortage_sort)
      assert.are.equal("b", items[1].name)
      assert.are.equal("c", items[2].name)
      assert.are.equal("a", items[3].name)
    end)

    it("sorts by name ascending when priority and missing equal", function()
      local items = {
        {name = "c", priority = 2, missing = 5},
        {name = "a", priority = 2, missing = 5},
        {name = "b", priority = 2, missing = 5}
      }
      table.sort(items, Util.shortage_sort)
      assert.are.equal("a", items[1].name)
      assert.are.equal("b", items[2].name)
      assert.are.equal("c", items[3].name)
    end)

    it("defaults priority to 1", function()
      local items = {
        {name = "a", missing = 10},
        {name = "b", priority = 2, missing = 5}
      }
      table.sort(items, Util.shortage_sort)
      assert.are.equal("b", items[1].name)
    end)
  end)

  describe("brain_key", function()
    it("combines force name and network id", function()
      local network = {
        force = {name = "player"},
        network_id = 42
      }
      assert.are.equal("player|42", Util.brain_key(network))
    end)
  end)

  describe("construction_reservation_key", function()
    it("combines network id, name, and quality", function()
      local network = {network_id = 7}
      assert.are.equal("7|iron-plate|normal", Util.construction_reservation_key(network, "iron-plate", "normal"))
      assert.are.equal("7|iron-plate|legendary", Util.construction_reservation_key(network, "iron-plate", "legendary"))
    end)
  end)

  describe("construction_scan_key", function()
    it("combines surface index, force name, and network id", function()
      assert.are.equal("1|player|42", Util.construction_scan_key(1, "player", 42))
    end)
  end)

  describe("status_item_name", function()
    it("returns name for normal quality", function()
      assert.are.equal("iron-plate", Util.status_item_name("iron-plate", "normal"))
    end)

    it("returns name@quality for non-normal", function()
      assert.are.equal("iron-plate@legendary", Util.status_item_name("iron-plate", "legendary"))
    end)

    it("returns empty string for nil name", function()
      assert.are.equal("", Util.status_item_name(nil))
    end)

    it("handles quality object", function()
      assert.are.equal("iron-plate@epic", Util.status_item_name("iron-plate", {name = "epic"}))
    end)

    it("defaults to normal when quality is nil", function()
      assert.are.equal("iron-plate", Util.status_item_name("iron-plate", nil))
    end)
  end)
end)
