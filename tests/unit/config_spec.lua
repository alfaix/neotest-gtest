local assert = require("luassert")
local config_module = require("neotest-gtest.config")

describe("config library", function()
  after_each(function()
    config_module.reset()
  end)

  it("config exists without setup", function()
    assert.are.equal(3, config_module.history_size)
  end)

  it("setup() overrides defaults", function()
    require("neotest-gtest.config").setup({ history_size = 5 })
    assert.are.equal(5, config_module.history_size)
  end)
end)
