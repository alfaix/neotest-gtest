local assert = require("luassert")
local it = require("nio.tests").it
local MockProject = require("tests.utils.mock_project")
local adapter = require("neotest-gtest")
local config = require("neotest-gtest.config")
local inventory = require("neotest-gtest.executables.inventory")

describe("runtime position discovery", function()
  local old_root
  local old_list

  before_each(function()
    old_root = config.root
    old_list = inventory.list
  end)

  after_each(function()
    config.root = old_root
    inventory.list = old_list
  end)

  it("keeps same named sources in different executables separate", function()
    local project = MockProject:new()
    project:set_contents({
      ["test_one.cpp"] = "TEST_P(Fixture, Runs) {}",
      ["test_two.cpp"] = "TEST_P(Fixture, Runs) {}",
    })
    project:set_executables({
      ["test_one.cpp"] = "/bin/one",
      ["test_two.cpp"] = "/bin/two",
    })
    config.root = function()
      return project:root()
    end

    inventory.list = function(executable)
      if executable == "/bin/one" then
        return { "One/Fixture.Runs/Alpha" }
      end

      return { "Two/Fixture.Runs/Beta" }
    end

    local one = adapter.discover_positions(project:root() .. "/test_one.cpp")
    local two = adapter.discover_positions(project:root() .. "/test_two.cpp")
    local one_source = assert(one:get_key(project:root() .. "/test_one.cpp::Fixture::Runs"))
    local two_source = assert(two:get_key(project:root() .. "/test_two.cpp::Fixture::Runs"))

    assert.same(
      { "One/Fixture.Runs/Alpha" },
      vim.tbl_map(function(node)
        return node:data().name
      end, one_source:children())
    )
    assert.same(
      { "Two/Fixture.Runs/Beta" },
      vim.tbl_map(function(node)
        return node:data().name
      end, two_source:children())
    )
  end)

  it("retains sources when their executable is not configured", function()
    local project = MockProject:new()
    project:set_contents({ ["test_one.cpp"] = "TEST_P(Fixture, Runs) {}" })
    config.root = function()
      return project:root()
    end

    inventory.list = function()
      error("inventory must not run without an executable")
    end

    local file = project:root() .. "/test_one.cpp"
    local tree = adapter.discover_positions(file)
    local source = assert(tree:get_key(file .. "::Fixture::Runs"))

    assert.equals(0, #source:children())
  end)
end)
