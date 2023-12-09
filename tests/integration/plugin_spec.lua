local neotest = require("neotest")
local assert = require("luassert")
local it = require("nio.tests").it
local controller = require("tests.utils.controller")

---@type neotest-gtest.IntegrationTestsController
local state
local exe1
local exe2

local function setup()
  controller.setup()
  state = controller.state

  exe1 = state.project_root .. "/tests/integration/cpp/build/test-executable"
  exe2 = state.project_root .. "/tests/integration/cpp/build/test-executable2"
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

  it("unconfiugred run thorws an error", function()
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

  it("configure wrong executable", function()
    setup()
    local root_id = state.project_root
    local id3 = state:mkid("subdirectory/test_three.cpp")
    state:configure_executables({ [exe1] = { root_id } })
    state:run({ args = { root_id } })
    state:assert_results_published({ state:mkid("test_one.cpp"), state:mkid("test_two.cpp") })
    state.ui.notifications:assert_notified(
      "did not produce results for the following tests: " .. id3,
      vim.log.levels.WARN
    )
    state.ui.notifications:assert_no_other_notifications()
  end)
end)

describe("with configured tree", function()
  local root_id, all_ids
  local function with_configured_tree()
    setup()
    root_id = state.project_root
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
