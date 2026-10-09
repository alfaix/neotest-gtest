local assert = require("luassert")
local it = require("nio.tests").it
local lib = require("neotest.lib")
local inventory = require("neotest-gtest.executables.inventory")
local parse = require("neotest-gtest.parse")

describe("compiled Google Test inventory", function()
  it("resolves both methods across two differently sized instantiations", function()
    local root = vim.uv.cwd() .. "/tests/integration/cpp"
    local source = root .. "/src/test_two.cpp"
    local names = inventory.list(root .. "/build/test-executable")

    local by_source = inventory.map_source(parse.parse_positions(source), names)

    assert.same({
      [source .. "::ParamFixture::Positive"] = {
        "First/ParamFixture.Positive/0",
        "First/ParamFixture.Positive/1",
        "Second/ParamFixture.Positive/0",
      },

      [source .. "::ParamFixture::Small"] = {
        "First/ParamFixture.Small/0",
        "First/ParamFixture.Small/1",
        "Second/ParamFixture.Small/0",
      },
    }, by_source)
  end)

  it("maps every generated case to one source declaration", function()
    local root = vim.uv.cwd() .. "/tests/integration/cpp"
    local source = root .. "/fixtures/param_inventory.cpp"
    local executable = root .. "/build/test-inventory"
    local names = inventory.list(executable)

    assert.same({
      "Pairs/PairFixture.Combined/0",
      "Pairs/PairFixture.Combined/1",
      "Pairs/PairFixture.Combined/2",
      "Pairs/PairFixture.Combined/3",

      "Custom/NamedFixture.Runs/Seven",
      "Custom/NamedFixture.Runs/Nine",

      "Custom/NamedFixture.Skips/Seven",
      "Custom/NamedFixture.Skips/Nine",

      "Custom/NamedFixture.DISABLED_NotRun/Seven",
      "Custom/NamedFixture.DISABLED_NotRun/Nine",
    }, names)

    local tree = parse.parse_positions(source)
    local by_source, unmatched = inventory.map_source(tree, names)

    assert.same({}, unmatched)

    assert.same({
      [source .. "::PairFixture::Combined"] = {
        "Pairs/PairFixture.Combined/0",
        "Pairs/PairFixture.Combined/1",
        "Pairs/PairFixture.Combined/2",
        "Pairs/PairFixture.Combined/3",
      },

      [source .. "::NamedFixture::Runs"] = {
        "Custom/NamedFixture.Runs/Seven",
        "Custom/NamedFixture.Runs/Nine",
      },

      [source .. "::NamedFixture::Skips"] = {
        "Custom/NamedFixture.Skips/Seven",
        "Custom/NamedFixture.Skips/Nine",
      },

      [source .. "::NamedFixture::DISABLED_NotRun"] = {
        "Custom/NamedFixture.DISABLED_NotRun/Seven",
        "Custom/NamedFixture.DISABLED_NotRun/Nine",
      },

      [source .. "::EmptyFixture::NeverInstantiated"] = {},
    }, by_source)

    local code, result = lib.process.run(
      { "ctest", "--test-dir", root .. "/build", "--show-only=json-v1" },
      { stdout = true }
    )

    assert.equals(0, code)

    local ctest_filters = {}

    for _, test in ipairs(vim.json.decode(result.stdout).tests) do
      if test.command[1] == executable then
        for _, arg in ipairs(test.command) do
          local filter = arg:match("^%-%-gtest_filter=(.*)$")

          if filter then
            ctest_filters[filter] = true
          end
        end
      end
    end

    for _, name in ipairs(names) do
      assert.is_true(ctest_filters[name])
    end
  end)
end)
