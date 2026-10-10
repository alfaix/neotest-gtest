local neotest = require("neotest")
local assert = require("luassert")
local it = require("nio.tests").it
local nio = require("nio")
local controller = require("tests.utils.controller")

---@type neotest-gtest.IntegrationTestsController
local state
local exe1
local exe2
local exe3
local exe4
local root_id

local function setup()
  controller.setup()
  state = controller.state

  for _ = 1, 100 do
    if neotest.state.positions(state.adapter_id) then
      break
    end

    nio.sleep(20)
  end

  exe1 = state.cpp_root .. "/build/test-executable"
  exe2 = state.cpp_root .. "/build/test-executable2"
  exe3 = state.cpp_root .. "/build/test-typed"
  exe4 = state.cpp_root .. "/build/test-isolation"
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

  it("isolates cases and reports later cases after a child crashes", function()
    setup()

    local file_id = state:mkid("test_isolation.cpp")
    local prefix = file_id .. "::Isolation::"
    local config = require("neotest-gtest.config")
    local old_isolation = config.process_isolation

    state:configure_executables({ [exe4] = { file_id } })
    state:run({ args = { file_id } })

    local grouped = state._results_recorder:get_aggregated_results()
    assert.equals("failed", assert(grouped[prefix .. "BObserveFreshState"]).status)
    assert.equals("passed", assert(grouped[prefix .. "EAfterCrash"]).status)

    state._results_recorder:reset()
    state._specs_recorder:reset()

    nio.scheduler()
    config.process_isolation = true
    vim.env.NEOTEST_GTEST_ISOLATION_FAILURE = "1"
    vim.env.NEOTEST_GTEST_ISOLATION_CRASH = "1"

    state:run({ args = { file_id } })

    local specs = state._specs_recorder:await_specs()
    local isolated = state._results_recorder:get_aggregated_results()

    nio.scheduler()
    config.process_isolation = old_isolation
    vim.env.NEOTEST_GTEST_ISOLATION_FAILURE = nil
    vim.env.NEOTEST_GTEST_ISOLATION_CRASH = nil

    assert.equals(1, #specs)
    assert.equals(5, #specs[1].context.isolated_cases)
    assert.equals("passed", assert(isolated[prefix .. "AWriteState"]).status)
    assert.equals("passed", assert(isolated[prefix .. "BObserveFreshState"]).status)
    assert.equals("failed", assert(isolated[prefix .. "CFail"]).status)
    assert.matches("isolated assertion failed", isolated[prefix .. "CFail"].short, 1, true)
    assert.equals("failed", assert(isolated[prefix .. "DCrash"]).status)
    assert.equals("passed", assert(isolated[prefix .. "EAfterCrash"]).status)

    local published = state._client:get_results(state.adapter_id)
    assert.equals("failed", assert(published[file_id .. "::Isolation"]).status)
    assert.equals("failed", assert(published[file_id]).status)
  end)

  it("runs parameterized runtime leaves separately through a per-run override", function()
    setup()

    local file_id = state:mkid("test_two.cpp")
    local source_id = file_id .. "::ParamFixture::Positive"
    state:configure_executables({ [exe1] = { file_id } })

    nio.scheduler()
    vim.cmd.edit(file_id)
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = 0 })

    local positions
    for _ = 1, 100 do
      positions = neotest.state.positions(state.adapter_id)

      if positions and positions:get_key(source_id .. "::First/ParamFixture.Positive/0") then
        break
      end

      nio.sleep(20)
    end

    assert.is_not_nil(positions:get_key(source_id .. "::First/ParamFixture.Positive/0"))

    state:run({ args = { source_id, process_isolation = true } })

    local specs = state._specs_recorder:await_specs()
    local results = state._results_recorder:get_aggregated_results()
    local published = state._client:get_results(state.adapter_id)

    assert.equals(1, #specs)
    assert.equals(3, #specs[1].context.isolated_cases)
    assert.equals("passed", assert(results[source_id .. "::First/ParamFixture.Positive/0"]).status)
    assert.equals("passed", assert(results[source_id .. "::First/ParamFixture.Positive/1"]).status)
    assert.equals("passed", assert(results[source_id .. "::Second/ParamFixture.Positive/0"]).status)
    assert.equals("passed", assert(published[source_id]).status)
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

  it("selects and reports both typed families in a Neotest session", function()
    setup()

    local file_id = state:mkid("test_typed.cpp")
    local typed_id = file_id .. "::TypedFixture::Passes"
    local pattern_id = file_id .. "::PatternFixture::Passes"
    local typed_leaf_id = typed_id .. "::TypedFixture/Large.Passes"
    local pattern_leaf_id = pattern_id .. "::Second/PatternFixture/1.Passes"

    state:configure_executables({ [exe3] = { file_id } })

    nio.scheduler()
    vim.cmd.edit(file_id)
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = 0 })

    local positions
    for _ = 1, 100 do
      positions = neotest.state.positions(state.adapter_id)

      if positions and positions:get_key(typed_leaf_id) and positions:get_key(pattern_leaf_id) then
        break
      end

      nio.sleep(20)
    end

    local typed_source = assert(positions:get_key(typed_id))
    local pattern_source = assert(positions:get_key(pattern_id))
    local typed_leaf = assert(positions:get_key(typed_leaf_id))
    local pattern_leaf = assert(positions:get_key(pattern_leaf_id))

    assert.equals(2, #typed_source:children())
    assert.equals(4, #pattern_source:children())

    local summary = require("neotest.consumers.summary")
    summary.open()
    summary:expand(typed_id, true)
    summary:expand(pattern_id, true)

    local summary_text
    for _ = 1, 100 do
      for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buffer].filetype == "neotest-summary" then
          summary_text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
          break
        end
      end

      if summary_text and summary_text:find("Second/PatternFixture/1.Passes", 1, true) then
        break
      end

      nio.sleep(20)
    end

    assert.is_not_nil(summary_text)
    assert.is_not_nil(summary_text:find("TypedFixture/Large.Passes", 1, true))
    assert.is_not_nil(summary_text:find("First/PatternFixture/0.Passes", 1, true))
    assert.is_not_nil(summary_text:find("Second/PatternFixture/1.Passes", 1, true))

    summary.close()

    for _, source in ipairs({ typed_source, pattern_source }) do
      nio.scheduler()
      vim.api.nvim_win_set_cursor(0, { source:data().range[1] + 1, 0 })

      local nearest = neotest.run.get_tree_from_args()
      assert.equals(source:data().id, assert(nearest):data().id)
    end

    for _, leaf in ipairs({ typed_leaf, pattern_leaf }) do
      local dap_spec = assert(require("neotest-gtest").build_spec({
        tree = leaf,
        strategy = "dap",
      })[1])

      assert.equals(exe3, dap_spec.strategy.program)
      assert.equals("--gtest_filter=" .. leaf:data().name, dap_spec.strategy.args[1])

      state._specs_recorder:reset()
      state._results_recorder:reset()
      state:run({ args = { leaf:data().id } })

      local specs = state._specs_recorder:await_specs()
      local results = state._results_recorder:get_aggregated_results()

      assert.equals(1, #specs)
      assert.equals("--gtest_filter=" .. leaf:data().name, specs[1].command[2])
      assert.equals("passed", assert(results[leaf:data().id]).status)
    end

    for _, source in ipairs({ typed_source, pattern_source }) do
      state._specs_recorder:reset()
      state._results_recorder:reset()
      state:run({ args = { source:data().id } })

      local specs = state._specs_recorder:await_specs()
      local results = state._results_recorder:get_aggregated_results()
      local report =
        vim.json.decode(require("neotest.lib").files.read(specs[1].context.results_path))

      assert.equals(#source:children(), report.tests)
      assert.equals("passed", assert(results[source:data().id]).status)
    end

    state._specs_recorder:reset()
    state._results_recorder:reset()

    nio.scheduler()
    vim.env.NEOTEST_GTEST_FAIL_TYPED = "1"
    state:run({ args = { file_id } })
    local failed_results = state._results_recorder:get_aggregated_results()

    nio.scheduler()
    vim.env.NEOTEST_GTEST_FAIL_TYPED = nil

    local typed_failure = file_id .. "::TypedFixture::FailsWhenRequested"
    local pattern_failure = file_id .. "::PatternFixture::FailsWhenRequested"

    assert.equals("failed", assert(failed_results[typed_failure]).status)
    assert.equals("failed", assert(failed_results[pattern_failure]).status)
    assert.equals(
      "failed",
      assert(failed_results[typed_failure .. "::TypedFixture/Large.FailsWhenRequested"]).status
    )
    assert.equals(
      "failed",
      assert(failed_results[pattern_failure .. "::First/PatternFixture/1.FailsWhenRequested"]).status
    )
    assert.matches(
      "selected type pattern failed",
      failed_results[pattern_failure .. "::First/PatternFixture/1.FailsWhenRequested"].short,
      1,
      true
    )
    assert.is_not_nil(
      failed_results[pattern_failure .. "::First/PatternFixture/1.FailsWhenRequested"].errors[1].line
    )
    assert.equals(
      "passed",
      assert(failed_results[pattern_failure .. "::Second/PatternFixture/1.FailsWhenRequested"]).status
    )

    state._specs_recorder:reset()
    state._results_recorder:reset()
    state:run({ args = { file_id } })

    local file_specs = state._specs_recorder:await_specs()
    local file_results = state._results_recorder:get_aggregated_results()
    local file_report =
      vim.json.decode(require("neotest.lib").files.read(file_specs[1].context.results_path))

    assert.equals(12, file_report.tests)
    assert.equals("passed", assert(file_results[typed_leaf_id]).status)
    assert.equals("passed", assert(file_results[pattern_leaf_id]).status)
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
    state.ui.notifications:assert_notified("test_three.cpp", vim.log.levels.WARN)
    state.ui.notifications:assert_notified("test_typed.cpp", vim.log.levels.WARN)
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
      state:mkid("test_typed.cpp"),
      state:mkid("test_isolation.cpp"),
    }
    state:configure_executables({ [exe1] = { root_id } })
    state:configure_executables({ [exe2] = { all_ids[1] } })
    state:configure_executables({ [exe3] = { all_ids[4] } })
    state:configure_executables({ [exe4] = { all_ids[5] } })
  end

  it("configure whole tree and then subtree + run whole tree", function()
    with_configured_tree()
    state:run({ args = { root_id }, expected_specs = 4 })
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
    local one, two, three, typed, isolation =
      state:mkid("test_one.cpp"),
      state:mkid("test_two.cpp"),
      state:mkid("subdirectory/test_three.cpp"),
      state:mkid("test_typed.cpp"),
      state:mkid("test_isolation.cpp")
    state:verify_unconfigured({ one, two, three, typed, isolation })
    ctest.configure_all().wait()
    state:verify_configured({
      [exe1] = { one, two },
      [exe2] = { three },
      [exe3] = { typed },
      [exe4] = { isolation },
    })
    state.ui.notifications:assert_notified("mapped 5 files", vim.log.levels.INFO)
    state.ui.notifications:assert_no_other_notifications()

    --
    -- Run all tests and verify that they are executed successfully.
    --
    state:run({ args = { root_id }, expected_specs = 4 })
    state._specs_recorder:await_specs()
    state:assert_results_published({ one, two, three, typed, isolation })
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
