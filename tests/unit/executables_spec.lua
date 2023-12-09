local assert = require("luassert")
local it = require("nio.tests").it

local ExecutablesRegistry = require("neotest-gtest.executables.registry")
local GlobalRegistry = require("neotest-gtest.executables.global_registry")
local tree_utils = require("tests.utils.tree")
local utils = require("neotest-gtest.utils")

---@type string
local registry_dir
---@type neotest-gtest.ExecutablesRegistry
local registry

local function make_node_id(node_name)
  if node_name == "" then
    return registry_dir
  end
  return string.format("%s/%s", registry_dir, node_name)
end

local function with_file_tree(fname2contents)
  tree_utils.make_directory_tree(fname2contents, registry_dir)
end

local function assert_executables_for_node(node_id, expected_executables)
  local executables, missing = registry:find_executables(node_id)
  assert.is_not_nil(executables)
  assert.is_nil(missing)
  for _, nodes in pairs(expected_executables) do
    table.sort(nodes)
  end
  for _, nodes in pairs(executables) do
    table.sort(nodes)
  end
  assert.are.same(expected_executables, executables)
end

local function make_registry()
  registry_dir = assert(vim.fn.tempname())
  registry_dir = utils.normalize_path(registry_dir)

  registry = ExecutablesRegistry:new(registry_dir)
end

describe("executables with single test in file", function()
  local test_id
  local file_id
  local root_id

  -- NB: Can't use before_each
  -- https://github.com/nvim-neotest/neotest/issues/314
  local function setup()
    make_registry()
    with_file_tree({ ["test_one.cpp"] = "TEST(TestOne, Foo) {}" })
    root_id = make_node_id("")
    file_id = make_node_id("test_one.cpp")
    test_id = make_node_id("test_one.cpp::TestOne::Foo")
    assert(vim.startswith(test_id, registry_dir))
    assert(registry._root_dir == registry_dir)
  end

  it("uninitialized find_executables returns error", function()
    setup()
    local exe2nodes, missing = registry:find_executables(root_id)
    assert.is_nil(exe2nodes)
    assert.are.equal(#missing, 1)
  end)

  it("throws error when the node does not belong to the tree", function()
    setup()
    local success, message = pcall(function()
      registry:find_executables("doesnt_exist")
    end)
    assert.is_false(success)
    assert(message)
    assert.is_not_nil(string.find(message, "doesnt_exist"))
  end)

  it("setting and getting executable for the same node returns it", function()
    setup()
    registry:update_executable(test_id, "/bin/exe1")
    assert_executables_for_node(test_id, { ["/bin/exe1"] = { test_id } })
  end)

  it("setting executable also sets executable for child", function()
    setup()
    registry:update_executable(file_id, "/bin/exe1")
    assert_executables_for_node(test_id, { ["/bin/exe1"] = { test_id } })
  end)

  it("executables mapping is persisted via the storage", function()
    setup()
    registry:update_executable(file_id, "/bin/exe1")
    local storage = require("neotest-gtest.storage"):new(registry._storage:path())
    assert.are.same({ [file_id] = "/bin/exe1" }, storage:node2executable())
  end)
end)

describe("with three files in the tree", function()
  local ids

  local function setup()
    make_registry()
    with_file_tree({
      ["test_one.cpp"] = "TEST(TestOne, Foo) {} TEST(TestOne, Bar) {}",
      ["test_two.cpp"] = "TEST(TestTwo, Foo) {}",
      ["test_three.cpp"] = "TEST(TestThree, Foo) {}",
    })
    ids = {
      root = make_node_id(""),
      test_one = make_node_id("test_one.cpp"),
      test_one_ns = make_node_id("test_one.cpp::TestOne"),
      test_one_foo = make_node_id("test_one.cpp::TestOne::Foo"),
      test_one_bar = make_node_id("test_one.cpp::TestOne::Bar"),
      test_two = make_node_id("test_two.cpp"),
      test_two_ns = make_node_id("test_two.cpp::TestTwo"),
      test_two_foo = make_node_id("test_two.cpp::TestTwo::Foo"),
      test_three = make_node_id("test_three.cpp"),
      test_three_ns = make_node_id("test_three.cpp::TestThree"),
      test_three_foo = make_node_id("test_three.cpp::TestThree::Foo"),
    }
  end

  it("empty executables list when unconfigured", function()
    setup()
    assert.are.same({}, registry:list_executables())
  end)

  it("list_executables return all executables", function()
    setup()
    registry:update_executable(ids.test_one, "/bin/exe2")
    registry:update_executable(ids.test_two, "/bin/exe1")
    local expected = { "/bin/exe1", "/bin/exe2" }
    local actual = registry:list_executables()
    table.sort(actual)
    assert.are.same(expected, actual)
  end)

  it("list_executables does not return duplicated ", function()
    setup()
    registry:update_executable(ids.test_one, "/bin/exe1")
    registry:update_executable(ids.test_two, "/bin/exe1")
    assert.are.same({ "/bin/exe1" }, registry:list_executables())
  end)

  it("setting parent executable overwrites child", function()
    setup()
    registry:update_executable(ids.test_one, "/bin/exe2")
    registry:update_executable(ids.root, "/bin/exe1")
    assert_executables_for_node(ids.root, { ["/bin/exe1"] = { ids.root } })
  end)

  it("setting child executable overwrites parent", function()
    setup()
    registry:update_executable(ids.root, "/bin/exe1")
    registry:update_executable(ids.test_one, "/bin/exe2")
    assert_executables_for_node(ids.test_one, { ["/bin/exe2"] = { ids.test_one } })
  end)

  it("parent -> exe1, child -> exe2 moves exe1 to sbilings of child", function()
    setup()
    registry:update_executable(ids.root, "/bin/exe1")
    registry:update_executable(ids.test_one, "/bin/exe2")
    assert_executables_for_node(
      ids.root,
      { ["/bin/exe2"] = { ids.test_one }, ["/bin/exe1"] = { ids.test_two, ids.test_three } }
    )
  end)

  it("grandparent -> exe1, grandchild -> exe2 overrides siblings in the whole tree", function()
    setup()
    -- this is a bit artificial as a single file always maps to the same exe,
    -- however since the registry doesn't make a distinction between file nodes
    -- and test nodes, this will do in place of complex tree structures
    registry:update_executable(ids.root, "/bin/exe1")
    registry:update_executable(ids.test_one_foo, "/bin/exe2")
    assert_executables_for_node(ids.root, {
      ["/bin/exe2"] = { ids.test_one_foo },
      ["/bin/exe1"] = { ids.test_two, ids.test_three, ids.test_one_bar },
    })
  end)

  it("clearing a parent executable clears children executables", function()
    setup()
    registry:update_executable(ids.test_one, "/bin/exe1")
    registry:update_executable(ids.test_two, "/bin/exe1")
    registry:update_executable(ids.test_three, "/bin/exe1")
    registry:update_executable(ids.root, nil)
    local _, missing = registry:find_executables(ids.test_one)
    assert.are.equal(#missing, 1)
  end)
end)

describe("test global registry", function()
  ---@type string
  local dir1, dir2
  ---@type neotest-gtest.ExecutablesRegistry
  local reg1, reg2

  local function setup()
    dir1 = assert(vim.fn.tempname())
    dir2 = assert(vim.fn.tempname())
    tree_utils.make_directory_tree({ ["test_one.cpp"] = "TEST(F, G) {}" }, dir1)
    tree_utils.make_directory_tree({ ["test_one.cpp"] = "TEST(F, G) {}" }, dir2)
    reg1 = GlobalRegistry:for_dir(dir1)
    reg2 = GlobalRegistry:for_dir(dir2)
  end

  it("returns the same registry for the same root", function()
    setup()
    local reg3 = GlobalRegistry:for_dir(dir1)
    assert.are.equal(reg1, reg3)
  end)

  it("lists executables from all registries", function()
    setup()
    reg1:update_executable(dir1 .. "/test_one.cpp", "/bin/exe1")
    reg2:update_executable(dir2 .. "/test_one.cpp", "/bin/exe2")

    local exes = GlobalRegistry:list_executables({ dir1, dir2 })
    table.sort(exes)

    assert.are.same({ "/bin/exe1", "/bin/exe2" }, exes)
  end)
end)
