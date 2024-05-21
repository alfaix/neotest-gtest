local helpers = require("tests.utils.helpers")
local executables = require("neotest-gtest.executables")
local GlobalRegistry = require("neotest-gtest.executables.global_registry")
local Storage = require("neotest-gtest.storage")
local recorders = require("tests.utils.recorders")
local ui_mock = require("tests.utils.ui_mock")
local ResultsParser = require("tests.utils.results_parser")
local assert = require("luassert")
local neotest = require("neotest")
local Path = require("plenary.path")
local M = {}

local function integration_tests_path()
  return Path:new(debug.getinfo(2, "S").source:sub(2)):parent():parent()
end

---@class neotest-gtest.IntegrationTestsController
---@field cpp_root string
---@field project_root string
---@field adapter_id string
---@field _results_recorder neotest-gtest.ResultsRecorder
---@field _specs_recorder neotest-gtest.SpecsRecorder
---@field ui neotest-gtest.tests.MockUi
local TestsController = {}

---@return neotest-gtest.IntegrationTestsController
function TestsController:new()
  local state = {
    project_root = Path:new(integration_tests_path()):parent().filename,
    ui = ui_mock.mock_ui(),
    _results_recorder = recorders.results:new(),
    _specs_recorder = recorders.specs:new(),
  }
  state.cpp_root = state.project_root .. "/tests/integration/cpp"
  state.adapter_id = "neotest-gtest:" .. state.project_root
  setmetatable(state, { __index = self })
  return state
end

function TestsController:assert_build_spec_failed(error_text)
  local error = self._specs_recorder:await_error()
  if not string.find(error, error_text, 1, true) then
    error(string.format("Expected error to contain %s, got %s", error_text, error))
  end
end

function TestsController:verify_unconfigured(nodes)
  for _, node_id in ipairs(nodes) do
    assert.is_nil(self:_get_node_executable(node_id))
  end
end

function TestsController:verify_configured(exe2nodes)
  for exe, nodes in pairs(exe2nodes) do
    for _, node_id in ipairs(nodes) do
      assert.are.same(exe, self:_get_node_executable(node_id))
    end
  end
end

function TestsController:_get_node_executable(node_id)
  local tree = assert(neotest.state.positions(self.adapter_id))
  local node = tree:get_key(node_id)
  local configured_exe2nodes, missing = executables.find_executables(node)
  if missing and #missing > 0 then
    return nil
  end
  assert(configured_exe2nodes)
  assert.are.equal(vim.tbl_count(configured_exe2nodes), 1)
  local exe, _ = next(configured_exe2nodes)
  return exe
end

function TestsController:assert_results_failed(error_message)
  local call = self._results_recorder:get_last_call()
  assert.is_not_nil(call.error)
  assert.is_not_nil(string.find(call.error, error_message, 1, true))
end

function TestsController:assert_results_published(files)
  local specs = self:_load_specs(files)

  local results, position2output_file = self._results_recorder:get_aggregated_results()
  helpers.assert_same_keys(specs, results)
  for position, spec in pairs(specs) do
    spec.output_file = position2output_file[position]
    spec:assert_matches_neotest_result(results[position])
  end
end

---@return table<string, neotest-gtest.tests.ReportSpec>
function TestsController:_load_specs(files)
  local specs = {}
  for _, file in ipairs(files) do
    local parser = ResultsParser:new(file)
    local position2spec = parser:parse_report_specs()
    specs = vim.tbl_extend("error", specs, position2spec)
  end
  return specs
end

function TestsController:reset()
  local storage = Storage:for_directory(self.project_root)
  storage:drop()
  GlobalRegistry:clear()

  self._results_recorder:reset()
  self._specs_recorder:reset()
  self._last_results = nil
  self.ui:reset()
end

function TestsController:configure_executables(exe2nodes)
  for exe, nodes in pairs(exe2nodes) do
    self:_configure_one_executable(exe, nodes)
  end
  self:verify_configured(exe2nodes)
end

function TestsController:_configure_one_executable(exe, nodes)
  self.ui.marks:set_marked({ [self.adapter_id] = nodes })
  self.ui.select:return_option("Enter path...")
  self.ui.input:return_value(exe)

  executables.configure_executable().wait()
end

function TestsController:mkid(filename, namespace, name)
  local fullpath = Path:new(self.cpp_root, "src", filename):absolute()
  if name ~= nil or namespace ~= nil then
    assert(namespace ~= nil, "cannot provide name but no namespace")
    return table.concat({ fullpath, namespace }, "::")
  end
  return fullpath
end

function TestsController:run(opts)
  local expected_specs = opts and opts.expected_specs or 1
  if expected_specs ~= 1 then
    self._results_recorder:expect_calls(expected_specs)
  end
  neotest.run.run(opts and opts.args)
end

M.state = TestsController:new()

local is_setup = false
function M.setup()
  M.state:reset()
  if is_setup then
    return
  end
  is_setup = true

  local client
  neotest.setup({
    log_level = 0,
    adapters = {
      require("neotest-gtest").setup({
        parsing_throttle_ms = 0,
        mappings = { configure = "<Plug>GtestConfigure" },
        filter_dir = function(name, rel_path, root)
          return name ~= "googletest"
        end,
      }),
    },
    consumers = {
      integration_tests = function(_client)
        client = _client
      end,
    },
  })

  -- call any function to trigger ensure_started()
  client:get_adapters()
end
return M
