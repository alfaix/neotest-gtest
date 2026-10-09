local assert = require("luassert")
local inventory = require("neotest-gtest.executables.inventory")
local tree_utils = require("tests.utils.tree")
local it = require("nio.tests").it

describe("Google Test runtime inventory", function()
  it("parses full compiled names and ignores parameter comments", function()
    local output = [[
Running main() from /build/gtest_main.cc
First/ParamFixture.
  Positive/0  # GetParam() = 0
  Positive/1  # GetParam() = 1

Second/ParamFixture.
  Positive/0  # GetParam() = 2

Custom/NamedFixture.
  Named/Alpha  # GetParam() = 10
  DISABLED_Named/Beta  # GetParam() = 20
]]

    assert.same({
      "First/ParamFixture.Positive/0",
      "First/ParamFixture.Positive/1",

      "Second/ParamFixture.Positive/0",

      "Custom/NamedFixture.Named/Alpha",
      "Custom/NamedFixture.DISABLED_Named/Beta",
    }, inventory.parse_list(output))
  end)

  it("maps compiled instances to one source declaration and retains zero-instance tests", function()
    local tree = tree_utils.make_directory_tree({
      ["test_inventory.cpp"] = [[
        TEST_P(ParamFixture, Positive) {}
        TEST_P(ParamFixture, Other) {}

        TEST_P(EmptyFixture, NeverInstantiated) {}
      ]],
    })

    local file = tree:children()[1]:data().path

    local by_source, unmatched = inventory.map_source(tree, {
      "First/ParamFixture.Positive/0",
      "Second/ParamFixture.Positive/0",
      "First/ParamFixture.Other/0",

      "Unknown.Case",
    })

    assert.same({
      [file .. "::ParamFixture::Positive"] = {
        "First/ParamFixture.Positive/0",
        "Second/ParamFixture.Positive/0",
      },

      [file .. "::ParamFixture::Other"] = { "First/ParamFixture.Other/0" },

      [file .. "::EmptyFixture::NeverInstantiated"] = {},
    }, by_source)

    assert.same({ "Unknown.Case" }, unmatched)
  end)
end)
