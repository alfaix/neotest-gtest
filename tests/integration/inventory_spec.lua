local assert = require("luassert")
local it = require("nio.tests").it
local lib = require("neotest.lib")
local inventory = require("neotest-gtest.executables.inventory")
local parse = require("neotest-gtest.parse")
local adapter = require("neotest-gtest")
local config = require("neotest-gtest.config")
local executables = require("neotest-gtest.executables")
local GlobalRegistry = require("neotest-gtest.executables.global_registry")

describe("compiled Google Test inventory", function()
  local old_root
  local old_lookup
  local old_find_executables
  local configured_registry

  after_each(function()
    if old_root then
      config.root = old_root
    end

    if old_lookup then
      configured_registry.configured_executable_for = old_lookup
    end

    if old_find_executables then
      executables.find_executables = old_find_executables
    end
  end)

  it("discovers three runtime leaves and runs one exact case", function()
    local root = vim.uv.cwd() .. "/tests/integration/cpp"
    local source = root .. "/src/test_two.cpp"
    local executable = root .. "/build/test-executable"
    local source_id = source .. "::ParamFixture::Positive"
    local registry = GlobalRegistry:for_dir(root)

    old_root = config.root
    old_lookup = registry.configured_executable_for
    old_find_executables = executables.find_executables
    configured_registry = registry

    config.root = function()
      return root
    end

    registry.configured_executable_for = function()
      return executable
    end

    executables.find_executables = function(node)
      return { [executable] = { node:data().id } }, {}
    end

    local tree = adapter.discover_positions(source)
    local parent = assert(tree:get_key(source_id))
    local names = vim.tbl_map(function(node)
      return node:data().name
    end, parent:children())

    assert.same({
      "First/ParamFixture.Positive/0",
      "First/ParamFixture.Positive/1",
      "Second/ParamFixture.Positive/0",
    }, names)

    local leaf = assert(tree:get_key(source_id .. "::First/ParamFixture.Positive/1"))
    local spec = assert(adapter.build_spec({ tree = leaf })[1])
    local code = lib.process.run(spec.command, { stdout = true })
    local report = vim.json.decode(lib.files.read(spec.context.results_path))

    assert.equals("--gtest_filter=First/ParamFixture.Positive/1", spec.command[2])
    assert.equals(0, code)
    assert.equals(1, report.tests)
    assert.equals("Positive/1", report.testsuites[1].testsuite[1].name)
  end)

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
