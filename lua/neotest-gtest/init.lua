local utils = require("neotest-gtest.utils")
local parse = require("neotest-gtest.parse")
local Report = require("neotest-gtest.report")
local Adapter = require("neotest-gtest.neotest_adapter")
local config = require("neotest-gtest.config")

local GTestNeotestAdapter = { name = "neotest-gtest" }
---@param args neotest.RunArgs
---@return nil | neotest.RunSpec[]
function GTestNeotestAdapter.build_spec(args)
  args.extra_args = args.extra_args or config.extra_args
  return Adapter:new(args):build_specs()
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
function GTestNeotestAdapter.results(spec, result, tree)
  local converter = Report.converter:new(spec, result, tree)
  return converter:make_neotest_results()
end

GTestNeotestAdapter.root = utils.normalized_root
GTestNeotestAdapter.setup = function(user_config)
  config.setup(user_config)
  require("neotest-gtest.executables").set_summary_autocmd()
  return GTestNeotestAdapter
end

GTestNeotestAdapter.discover_positions = parse.parse_positions
GTestNeotestAdapter.is_test_file = function(path)
  return config.is_test_file(path)
end
GTestNeotestAdapter.filter_dir = function(name, relpath, root)
  return config.filter_dir(name, relpath, root)
end

return GTestNeotestAdapter
