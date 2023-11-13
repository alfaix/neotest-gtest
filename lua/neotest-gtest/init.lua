local utils = require("neotest-gtest.utils")
local lib = require("neotest.lib")
local parse = require("neotest-gtest.parse")
local Report = require("neotest-gtest.report")
local Adapter = require("neotest-gtest.neotest_adapter")

local GTestNeotestAdapter = { name = "neotest-gtest" }
GTestNeotestAdapter.is_test_file = utils.is_test_file
function GTestNeotestAdapter.discover_positions(file_path)
  parse.parse_positions(file_path)
end

---@param args neotest.RunArgs
---@return nil | neotest.RunSpec[]
function GTestNeotestAdapter.build_spec(args)
  return Adapter:new(args):build_specs()
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return neotest.Result[]
function GTestNeotestAdapter.results(spec, result, tree)
  -- nothing ran
  local success, data = pcall(lib.files.read, spec.context.results_path)
  if not success then
    vim.notify(
      string.format(
        [[Gtest executable failed to produce a result. Command: %s, exit code: %d, output at: %s\n
            Please make sure any additional arguments supplied are correct and check the output for additional info.]],
        table.concat(spec.command, " "),
        result.code,
        result.output
      )
    )
    return {}
  end
  local gtest_output = vim.json.decode(data) or { testsuites = {} }
  local reports = {}
  for _, testsuite in ipairs(gtest_output.testsuites) do
    for _, test in ipairs(testsuite.testsuite) do
      local report = Report:new(test, tree)
      -- TODO generally works, short report of `report` is not really short, not
      -- sure why. Can't call vim.notify() here because async/scheduling bullshit
      reports[report:position_id()] = report:to_neotest_report(result.output)
    end
  end
  return reports
end

function GTestNeotestAdapter.setup(config)
  require("neotest-gtest.config").setup(config)
end

function GTestNeotestAdapter.root(path)
  local root_path = require("neotest-gtest.config").get_config().root(path)
  if root_path ~= nil then
    return utils.normalize_path(root_path)
  end
end

return GTestNeotestAdapter
