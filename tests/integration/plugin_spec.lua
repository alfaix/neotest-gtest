local neotest = require("neotest")
local assert = require("luassert")
local it = require("nio.tests").it
local controller = require("tests.utils.controller")

---@type neotest-gtest.IntegrationTestsController
local state
local exe1
local exe2
local root_id

local function setup()
  controller.setup()
  state = controller.state

  exe1 = state.cpp_root .. "/build/test-executable"
  exe2 = state.cpp_root .. "/build/test-executable2"
  root_id = state.cpp_root .. "/src"
end

local function assert_notified_id_not_found(id)
  state.ui.notifications:assert_notified(
    "did not produce results for the following tests: " .. id,
    vim.log.levels.WARN
  )
  state.ui.notifications:assert_no_other_notifications()
end

describe("integration testsuite", function()
  it("check correctness of the setup", function()
    setup()
    local tree = neotest.state.positions(state.adapter_id)
    assert.are.same(neotest.state.adapter_ids(), { state.adapter_id })
    assert.is_not_nil(tree)
  end)

  it("configure and run subtree", function()
    setup()
    local id = state:mkid("test_one.cpp")
    state:configure_executables({ [exe1] = { id } })
    state:run({ args = { id } })
    state:assert_results_published({ id })
    state.ui.notifications:assert_no_other_notifications()
  end)

  it("runs and reports every instance of a parameterized source test", function()
    setup()
    local file_id = state:mkid("test_two.cpp")
    local id = file_id .. "::ParamFixture::Positive"
    state:configure_executables({ [exe1] = { file_id } })
    state:run({ args = { id } })

    local results = state._results_recorder:get_aggregated_results()
    local result = assert(results[id])
    assert.are.equal("passed", result.status)
    assert.is_not_nil(result.short:find("First/ParamFixture.Positive/0", 1, true))
    assert.is_not_nil(result.short:find("First/ParamFixture.Positive/1", 1, true))
    assert.is_not_nil(result.short:find("Second/ParamFixture.Positive/0", 1, true))
    state.ui.notifications:assert_no_other_notifications()
  end)

  it("unconfigured run throws an error", function()
    setup()
    local id = state:mkid("test_two.cpp")
    state:verify_unconfigured({ id })
    state:run({ args = { id } })
    state:assert_build_spec_failed("Some nodes do not have a corresponding GTest executable")
    state.ui.notifications:assert_notified(
      "Some nodes do not have a corresponding GTest executable",
      vim.log.levels.WARN
    )
    state.ui.notifications:assert_no_other_notifications()
  end)

  it("configure nonexisting executable", function()
    setup()
    local id = state:mkid("test_two.cpp")
    state:configure_executables({ ["/path/that/does/not/exist"] = { id } })
    state:run({ args = { id } })
    state:assert_results_failed("/path/that/does/not/exist not found")
    state.ui.notifications:assert_notified(
      "/path/that/does/not/exist not found",
      vim.log.levels.WARN
    )
    state.ui.notifications:assert_no_other_notifications()
  end)

  it("configure wrong executable (namespace)", function()
    setup()
    state:configure_executables({ [exe1] = { root_id } })
    state:run({ args = { root_id } })
    state:assert_results_published({ state:mkid("test_one.cpp"), state:mkid("test_two.cpp") })
    assert_notified_id_not_found(state:mkid("subdirectory/test_three.cpp"))
  end)

  it("configure wrong executable (specific test)", function()
    setup()
    state:configure_executables({ [exe1] = { root_id } })
    local id = state:mkid("subdirectory/test_three.cpp", "TestThree", "TestOk")
    state:run({ args = { id } })
    assert_notified_id_not_found(id)
  end)
end)

describe("with configured tree", function()
  local root_id, all_ids
  local function with_configured_tree()
    setup()
    root_id = state.cpp_root .. "/src"
    all_ids = {
      state:mkid("subdirectory/test_three.cpp"),
      state:mkid("test_two.cpp"),
      state:mkid("test_one.cpp"),
    }
    state:configure_executables({ [exe1] = { root_id } })
    state:configure_executables({ [exe2] = { all_ids[1] } })
  end

  it("configure whole tree and then subtree + run whole tree", function()
    with_configured_tree()
    state:run({ args = { root_id }, expected_specs = 2 })
    state._specs_recorder:await_specs()
    state:assert_results_published(all_ids)
    state.ui.notifications:assert_no_other_notifications()
  end)

  it("configure whole tree and then subtree + run single file", function()
    with_configured_tree()
    state:run({ args = { all_ids[1] } })
    state._specs_recorder:await_specs()
    state:assert_results_published({ all_ids[1] })
    state.ui.notifications:assert_no_other_notifications()
  end)
end)

describe("configure all", function()
  local ctest = require("neotest-gtest.executables.ctest")
  it("maps every file to the executable that compiles it", function()
    --
    -- Setup and run configure_all to map all files to their executables.
    --
    setup()
    local one, two, three =
      state:mkid("test_one.cpp"),
      state:mkid("test_two.cpp"),
      state:mkid("subdirectory/test_three.cpp")
    state:verify_unconfigured({ one, two, three })
    ctest.configure_all().wait()
    state:verify_configured({ [exe1] = { one, two }, [exe2] = { three } })
    state.ui.notifications:assert_notified("mapped 3 files", vim.log.levels.INFO)
    state.ui.notifications:assert_no_other_notifications()

    --
    -- Run all tests and verify that they are executed successfully.
    --
    state:run({ args = { root_id }, expected_specs = 2 })
    state._specs_recorder:await_specs()
    state:assert_results_published({ one, two, three })
  end)

  it("runs the mapped files and warns about the unmapped ones", function()
    setup()
    local one = state:mkid("test_one.cpp")
    state:configure_executables({ [exe1] = { one } })
    state:run({ args = { root_id } })
    state:assert_results_published({ one })
    state.ui.notifications:assert_notified("Nodes missing executable", vim.log.levels.WARN)
    state.ui.notifications:assert_no_other_notifications()
  end)
end)
