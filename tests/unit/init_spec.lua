local assert = require("luassert")
local config_module = require("neotest-gtest.config")
local adapter = require("neotest-gtest")

describe("adapter interface", function()
  after_each(function()
    config_module.reset()
  end)

  it("root() normalizes user-supplied root", function()
    adapter.setup({
      root = function(path)
        return "/usr/"
      end,
    })
    assert.are.equal("/usr", adapter.root("anything"))
  end)
end)
