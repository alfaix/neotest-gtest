local neotest = require("neotest")
local assert = require("luassert")
local it = require("nio.tests").it
local nio = require("nio")
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

  it("refreshes parameterized leaves on file save and selects one exact case", function()
    setup()

    local file_id = state:mkid("test_two.cpp")
    local source_id = file_id .. "::ParamFixture::Positive"
    local leaf_id = source_id .. "::First/ParamFixture.Positive/1"

    state:configure_executables({ [exe1] = { file_id } })

    nio.scheduler()
    vim.cmd.edit(file_id)
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = 0 })

    local leaf
    for _ = 1, 100 do
      local positions = neotest.state.positions(state.adapter_id)
      leaf = positions and positions:get_key(leaf_id)

      if leaf then
        break
      end

      nio.sleep(20)
    end

    assert.is_not_nil(leaf)
    assert.equals(3, #leaf:parent():children())

    nio.scheduler()
    vim.api.nvim_win_set_cursor(0, { leaf:parent():data().range[1] + 1, 0 })

    local nearest = neotest.run.get_tree_from_args()
    assert.equals(source_id, assert(nearest):data().id)

    local dap_spec = assert(require("neotest-gtest").build_spec({
      tree = leaf,
      strategy = "dap",
    })[1])

    assert.equals(exe1, dap_spec.strategy.program)
    assert.equals("--gtest_filter=First/ParamFixture.Positive/1", dap_spec.strategy.args[1])

    local summary = require("neotest.consumers.summary")
    summary.open()
    summary:expand(source_id, true)

    local summary_text
    for _ = 1, 100 do
      for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buffer].filetype == "neotest-summary" then
          summary_text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
          break
        end
      end

      if summary_text and summary_text:find("Second/ParamFixture.Positive/0", 1, true) then
        break
      end

      nio.sleep(20)
    end

    assert.is_not_nil(summary_text)
    assert.is_not_nil(summary_text:find("First/ParamFixture.Positive/0", 1, true))
    assert.is_not_nil(summary_text:find("First/ParamFixture.Positive/1", 1, true))
    assert.is_not_nil(summary_text:find("Second/ParamFixture.Positive/0", 1, true))

    summary.close()

    state:run({ args = { leaf_id } })
    local specs = state._specs_recorder:await_specs()

    assert.equals(1, #specs)
    assert.equals(exe1, specs[1].command[1])
    assert.equals("--gtest_filter=First/ParamFixture.Positive/1", specs[1].command[2])

    local results = state._results_recorder:get_aggregated_results()
    assert.equals("passed", assert(results[leaf_id]).status)

    state._specs_recorder:reset()
    state._results_recorder:reset()

    state:run({ args = { source_id } })

    local parent_specs = state._specs_recorder:await_specs()
    local parent_results = state._results_recorder:get_aggregated_results()
    local report =
      vim.json.decode(require("neotest.lib").files.read(parent_specs[1].context.results_path))

    assert.equals(3, report.tests)
    assert.equals("passed", assert(parent_results[source_id]).status)
    assert.equals("passed", assert(parent_results[leaf_id]).status)

    state._specs_recorder:reset()
    state._results_recorder:reset()

    nio.scheduler()
    vim.env.NEOTEST_GTEST_FAIL_PARAM = "1"
    state:run({ args = { source_id } })
    local failing_results = state._results_recorder:get_aggregated_results()

    nio.scheduler()
    vim.env.NEOTEST_GTEST_FAIL_PARAM = nil

    assert.equals("failed", assert(failing_results[source_id]).status)
    assert.equals("failed", assert(failing_results[leaf_id]).status)
    assert.matches("selected parameter failed", failing_results[leaf_id].short, 1, true)
    assert.equals(
      "passed",
      assert(failing_results[source_id .. "::First/ParamFixture.Positive/0"]).status
    )
    assert.equals(
      "passed",
      assert(failing_results[source_id .. "::Second/ParamFixture.Positive/0"]).status
    )

    state._specs_recorder:reset()
    state._results_recorder:reset()

    state:run({ args = { file_id } })

    local file_specs = state._specs_recorder:await_specs()
    state._results_recorder:get_aggregated_results()

    local file_report =
      vim.json.decode(require("neotest.lib").files.read(file_specs[1].context.results_path))
    local seen = {}

    for _, suite in ipairs(file_report.testsuites) do
      for _, test in ipairs(suite.testsuite) do
        local name = suite.name .. "." .. test.name
        assert.is_nil(seen[name])
        seen[name] = true
      end
    end

    assert.equals(9, file_report.tests)
    assert.equals(9, vim.tbl_count(seen))
    assert.is_true(seen["First/ParamFixture.Positive/0"])
    assert.is_true(seen["First/ParamFixture.Positive/1"])
    assert.is_true(seen["Second/ParamFixture.Positive/0"])
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
