local assert = require("luassert")
local inventory = require("neotest-gtest.executables.inventory")
local tree_utils = require("tests.utils.tree")
local it = require("nio.tests").it
local nio = require("nio")

describe("Google Test runtime inventory", function()
  it("stops an inventory process that exceeds its timeout", function()
    nio.scheduler()

    local executable = assert(vim.fn.tempname())
    require("neotest.lib").files.write(executable, "#!/bin/sh\nsleep 1\n")
    assert.is_true(vim.uv.fs_chmod(executable, 493))

    local ok, err = pcall(inventory.list, executable, { timeout_ms = 20 })

    assert.is_false(ok)
    assert.matches("timed out", tostring(err), 1, true)
  end)

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

  it("maps typed cases with numeric and custom type names", function()
    local tree = tree_utils.make_directory_tree({
      ["test_typed.cpp"] = "TYPED_TEST(TypedFixture, Works) {}",
    })
    local file = tree:children()[1]:data().path

    local by_source, unmatched = inventory.map_source(tree, {
      "TypedFixture/0.Works",
      "TypedFixture/Long.Works",
      "OtherFixture/0.Works",
    })

    assert.same({
      [file .. "::TypedFixture::Works"] = {
        "TypedFixture/0.Works",
        "TypedFixture/Long.Works",
      },
    }, by_source)
    assert.same({ "OtherFixture/0.Works" }, unmatched)
  end)

  it("maps type-parameterized cases from separate instantiations", function()
    local tree = tree_utils.make_directory_tree({
      ["test_typed.cpp"] = "TYPED_TEST_P(PatternFixture, Works) {}",
    })
    local file = tree:children()[1]:data().path

    local by_source, unmatched = inventory.map_source(tree, {
      "First/PatternFixture/0.Works",
      "First/PatternFixture/1.Works",
      "Second/PatternFixture/0.Works",
      "Other/PatternFixture/0.Unknown",
    })

    assert.same({
      [file .. "::PatternFixture::Works"] = {
        "First/PatternFixture/0.Works",
        "First/PatternFixture/1.Works",
        "Second/PatternFixture/0.Works",
      },
    }, by_source)
    assert.same({ "Other/PatternFixture/0.Unknown" }, unmatched)
  end)

  it("reports a missing executable in one line, without a process error", function()
    nio.scheduler()

    local missing = assert(vim.fn.tempname())
    local ok, err = pcall(inventory.list, missing)

    assert.is_false(ok)
    assert.equals(missing .. " does not exist or cannot be read", err)
  end)

  describe("listing cache", function()
    -- Writes a fake executable that appends one line to a counter file per run.
    local function write_counting_executable(executable, counter, listing, exit_code)
      local script = string.format(
        "#!/bin/sh\necho run >> '%s'\nprintf '%%s' '%s'\nexit %d\n",
        counter,
        listing,
        exit_code or 0
      )

      require("neotest.lib").files.write(executable, script)
      assert.is_true(vim.uv.fs_chmod(executable, 493))
    end

    local function runs(counter)
      local count = 0
      local file = io.open(counter, "r")

      if file == nil then
        return 0
      end

      for _ in file:lines() do
        count = count + 1
      end

      file:close()
      return count
    end

    it("reuses a listing until the executable changes", function()
      nio.scheduler()

      local executable = assert(vim.fn.tempname())
      local counter = executable .. ".count"

      write_counting_executable(executable, counter, "Suite.\n  Case\n")
      assert.same({ "Suite.Case" }, inventory.list(executable))
      assert.same({ "Suite.Case" }, inventory.list(executable))
      assert.equals(1, runs(counter))

      write_counting_executable(executable, counter, "Suite.\n  Rebuilt\n  Another\n")
      assert.same({ "Suite.Rebuilt", "Suite.Another" }, inventory.list(executable))
      assert.equals(2, runs(counter))
    end)

    it("shares one process between concurrent listings of the same executable", function()
      nio.scheduler()

      local executable = assert(vim.fn.tempname())
      local counter = executable .. ".count"

      -- The sleep keeps the first run in flight while the other callers arrive.
      require("neotest.lib").files.write(
        executable,
        string.format(
          "#!/bin/sh\necho run >> '%s'\nsleep 0.2\nprintf 'Suite.\\n  Case\\n'\n",
          counter
        )
      )
      assert.is_true(vim.uv.fs_chmod(executable, 493))

      local results = nio.gather({
        function()
          return inventory.list(executable)
        end,
        function()
          return inventory.list(executable)
        end,
        function()
          return inventory.list(executable)
        end,
      })

      for _, names in ipairs(results) do
        assert.same({ "Suite.Case" }, names)
      end
      assert.equals(1, runs(counter))
    end)

    it("does not cache a failed listing", function()
      nio.scheduler()

      local executable = assert(vim.fn.tempname())
      local counter = executable .. ".count"

      write_counting_executable(executable, counter, "", 3)
      local ok, err = pcall(inventory.list, executable)

      assert.is_false(ok)
      assert.matches("exited with code 3", tostring(err), 1, true)

      write_counting_executable(executable, counter, "Suite.\n  Recovered\n")
      assert.same({ "Suite.Recovered" }, inventory.list(executable))
      assert.equals(2, runs(counter))
    end)

    it("drops the cached listing when invalidated", function()
      nio.scheduler()

      local executable = assert(vim.fn.tempname())
      local counter = executable .. ".count"

      write_counting_executable(executable, counter, "Suite.\n  Case\n")
      inventory.list(executable)
      inventory.invalidate(executable)
      inventory.list(executable)

      assert.equals(2, runs(counter))
    end)
  end)
end)
