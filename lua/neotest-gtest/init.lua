local utils = require("neotest-gtest.utils")
local parse = require("neotest-gtest.parse")
local Report = require("neotest-gtest.report")
local Adapter = require("neotest-gtest.neotest_adapter")
local config = require("neotest-gtest.config")
local inventory = require("neotest-gtest.executables.inventory")
local refresh = require("neotest-gtest.executables.refresh")
local GlobalRegistry = require("neotest-gtest.executables.global_registry")
local neotest = require("neotest")
local test_kinds = require("neotest-gtest.test_kinds")

local GTestNeotestAdapter = { name = "neotest-gtest" }

local function discovery_root(file_path)
  local prefix = GTestNeotestAdapter.name .. ":"
  local root

  local adapter_ids = neotest.state and neotest.state.adapter_ids and neotest.state.adapter_ids()
    or {}

  for _, adapter_id in ipairs(adapter_ids) do
    if vim.startswith(adapter_id, prefix) then
      local candidate = adapter_id:sub(#prefix + 1)
      local within_root = file_path == candidate or vim.startswith(file_path, candidate .. "/")

      if within_root and (root == nil or #candidate > #root) then
        root = candidate
      end
    end
  end

  return root or utils.normalized_root(file_path)
end

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
  if spec.context and spec.context.isolated_cases then
    local merged = {}

    for _, case in ipairs(spec.context.isolated_cases) do
      local process_result = case.process_result or { code = result.code, output = result.output }
      local case_results = Report.converter:new(case, process_result, tree):make_neotest_results()
      local id = case.context.position_ids[1]

      merged[id] = assert(case_results[id], "Missing isolated result for " .. id)
    end

    return merged
  end

  local converter = Report.converter:new(spec, result, tree)
  return converter:make_neotest_results()
end

GTestNeotestAdapter.root = utils.normalized_root
GTestNeotestAdapter.setup = function(user_config)
  config.setup(user_config)
  require("neotest-gtest.executables").set_summary_autocmd()
  return GTestNeotestAdapter
end

function GTestNeotestAdapter.discover_positions(file_path)
  local source_tree = parse.parse_positions(file_path)
  local root = discovery_root(file_path)

  if root == nil then
    return source_tree
  end

  local registry = GlobalRegistry:for_dir(root)
  local executable_sources = {}
  local configured_executables = {}

  local file_executable = registry:configured_executable_for(file_path)
  if file_executable then
    configured_executables[file_executable] = true
  end

  for _, node in source_tree:iter_nodes() do
    local data = node:data()

    local kind = data.extra and data.extra.kind
    if data.type == "test" then
      local configured = registry:configured_executable_for(data.id)

      if configured then
        configured_executables[configured] = true
      end
    end

    if data.type == "test" and test_kinds.is_generated(kind) then
      local executable = registry:configured_executable_for(data.id)

      if executable then
        executable_sources[executable] = executable_sources[executable] or {}
        executable_sources[executable][data.id] = true
      end
    end
  end

  local runtime_by_source = {}

  for executable in pairs(configured_executables) do
    refresh.track(executable, file_path)
  end

  for executable, source_ids in pairs(executable_sources) do
    local source_stat = vim.uv.fs_stat(file_path)
    local executable_stat = vim.uv.fs_stat(executable)
    local stale = source_stat
      and executable_stat
      and source_stat.mtime.sec > executable_stat.mtime.sec

    if stale then
      utils.schedule_notify(
        "Google Test inventory is stale; rebuild " .. executable,
        vim.log.levels.WARN
      )
    else
      local ok, names = pcall(inventory.list, executable)

      if not ok then
        utils.schedule_notify(
          "Google Test inventory unavailable for " .. executable .. ": " .. tostring(names),
          vim.log.levels.WARN
        )
      else
        local mapped = inventory.map_source(source_tree, names)

        for source_id in pairs(source_ids) do
          runtime_by_source[source_id] = mapped[source_id] or {}
        end
      end
    end
  end

  if next(runtime_by_source) == nil then
    return source_tree
  end

  return parse.enrich_positions(source_tree, runtime_by_source)
end

GTestNeotestAdapter.is_test_file = function(path)
  return config.is_test_file(path)
end
GTestNeotestAdapter.filter_dir = function(name, relpath, root)
  return config.filter_dir(name, relpath, root)
end

return GTestNeotestAdapter
