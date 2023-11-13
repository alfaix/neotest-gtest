local config = require("neotest-gtest.config")
local executables = require("neotest-gtest.executables")
local neotest_spec_utils = require("tests.unit.neotest_spec_utils")
local it = require("nio").tests.it

local MOCK_EXECUTABLE = "/build/some-gtest-executable"

local function convert_child_id_to_full_id(tree, child_id)
  local sep
  if tree:data().type == "dir" then
    sep = "/"
  else
    sep = "::"
  end
  return tree:data().path .. sep .. child_id
end

local function with_executable_per_node(exe2nodes)
  executables.find_executables = function(tree)
    for executable, nodes in pairs(exe2nodes) do
      exe2nodes[executable] = vim.tbl_map(function(child_id)
        return convert_child_id_to_full_id(tree, child_id)
      end, nodes)
    end
    return true, exe2nodes, nil
  end
end
local function with_mock_executable_for_nodes(node_ids)
  return with_executable_per_node({ [MOCK_EXECUTABLE] = node_ids })
end

local function with_executable_not_found()
  executables.find_executables = function(tree)
    return false, nil, { tree:data().id }
  end
end

describe("adapter spec", function()
  local old_root
  local old_find_executables

  before_each(function()
    old_find_executables = executables.find_executables
    old_root = config.get_config().root
    config.get_config().root = function()
      return "/root"
    end
  end)

  after_each(function()
    config.get_config().root = old_root
    executables.find_executables = old_find_executables
  end)

  it("builds command for a file", function()
    with_mock_executable_for_nodes({ "TestOne" })

    neotest_spec_utils.assert_spec_for_file(
      [[
      TEST(TestOne, Foo) {}
      ]],
      {
        command = { MOCK_EXECUTABLE, "--gtest_filter=TestOne.*" },
        allow_extra_args = true,
      }
    )
  end)

  it("builds command with extra args", function()
    with_mock_executable_for_nodes({ "TestOne" })

    neotest_spec_utils.assert_spec_for_file(
      [[
      TEST(TestOne, Foo) {}
      ]],
      {
        command = { MOCK_EXECUTABLE, "--gtest_filter=TestOne.*", "--gtest_repeat=2" },
        extra_args = { "--gtest_repeat=2" },
        allow_extra_args = true,
      }
    )
  end)

  it("builds command for a single test in a file", function()
    with_mock_executable_for_nodes({ "TestOne::Bar" })

    neotest_spec_utils.assert_spec_for_file(
      [[
      TEST(TestOne, Foo) {}
      TEST(TestOne, Bar) {}
      ]],
      {
        input_tree = "TestOne::Bar",
        command = { MOCK_EXECUTABLE, "--gtest_filter=TestOne.Bar" },
        allow_extra_args = true,
      }
    )
  end)

  it("builds command for a file with two namespaces", function()
    with_mock_executable_for_nodes({ "TestOne", "TestTwo" })

    neotest_spec_utils.assert_spec_for_file(
      [[
      TEST(TestOne, Foo) {}
      TEST(TestTwo, Foo) {}
      ]],
      {
        command = { MOCK_EXECUTABLE, "--gtest_filter=TestOne.*:TestTwo.*" },
        allow_extra_args = true,
      }
    )
  end)

  it("returns error if executable is missing", function()
    with_executable_not_found()

    neotest_spec_utils.assert_spec_for_file(
      [[ TEST(TestOne, Foo) {}
      ]],
      {
        expect_error = true,
      }
    )
  end)

  it("sets debug strategy when requested", function()
    with_mock_executable_for_nodes({ "TestOne" })

    neotest_spec_utils.assert_spec_for_file(
      [[
        TEST(TestOne, Foo) {}
      ]],
      {
        input_strategy = "dap",
        command = { MOCK_EXECUTABLE },
        expected_strategy = {
          name = "Debug with neotest-gtest",
          type = "codelldb",
          request = "launch",
          program = MOCK_EXECUTABLE,
          args = { "--gtest_filter=TestOne.*" },
        },
        allow_extra_args = true,
      }
    )
  end)

  it("runs a single command for two files in directory", function()
    with_mock_executable_for_nodes({ "test_one.cpp", "test_two.cpp" })

    neotest_spec_utils.assert_specs_for_files({
      ["test_one.cpp"] = [[
        TEST(TestOne, Foo) {}
        TEST(TestOne, Bar) {}
        TEST(TestTwo, Foo) {}
      ]],
      ["test_two.cpp"] = [[
        TEST(TestThree, Foo) {}
        TEST(TestThree, Bar) {}
      ]],
    }, {
      neotest_specs = {
        { command = { MOCK_EXECUTABLE, "--gtest_filter=TestOne.*:TestTwo.*:TestThree.*" } },
      },
      allow_extra_args = true,
    })
  end)

  it("runs two different commands for three files", function()
    with_executable_per_node({
      ["/bin/exe1"] = { "test_one.cpp", "test_two.cpp" },
      ["/bin/exe2"] = { "test_three.cpp" },
    })

    neotest_spec_utils.assert_specs_for_files({
      ["test_one.cpp"] = [[
        TEST(TestOne, Foo) {}
        TEST(TestOne, Bar) {}
        TEST(TestOneMore, Foo) {}
      ]],
      ["test_two.cpp"] = [[
        TEST(TestTwo, Foo) {}
        TEST(TestTwo, Bar) {}
      ]],
      ["test_three.cpp"] = [[
        TEST(TestThree, Foo) {}
        TEST(TestThree, Bar) {}
      ]],
    }, {
      neotest_specs = {
        { command = { "/bin/exe1", "--gtest_filter=TestOne.*:TestOneMore.*:TestTwo.*" } },
        { command = { "/bin/exe2", "--gtest_filter=TestThree.*" } },
      },
      allow_extra_args = true,
    })
  end)
end)
