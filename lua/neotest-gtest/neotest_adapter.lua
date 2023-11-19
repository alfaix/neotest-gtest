local executables = require("neotest-gtest.executables")
local utils = require("neotest-gtest.utils")
local config = require("neotest-gtest.config")

---Gets a filter argument for the given test node
---@param node neotest.Tree a tree node representing a test
---@return string filter Google Test filter string for the test
local function get_filter_for_test_node(node)
  local data = node:data()
  local posid = data.id
  local test_kind = data.extra.kind
  if test_kind == "TEST_P" then
    -- TODO: figure this out (will have to query executables and do
    -- best-effort matching, probably)
    error("TEST_P is not yet supported, sorry :(")
  else
    local parts = vim.split(posid, "::", { plain = true })
    -- file::namespace::test_name
    assert(#parts == 3, "bad node")
    local namespace = parts[2]
    local test_name = parts[3]
    return string.format("%s.%s", namespace, test_name)
  end
end

---Creates Google Test filters for the given nodes
---@param node neotest.Tree position to create a filter to
---@return string | string[] filters String or potentially nested list of strings.
---        Flatten to get the filters that gtest executable expects.
local function get_filters_for_node(node)
  local data = node:data()
  local type = data.type

  if type == "test" then
    return get_filter_for_test_node(node)
  elseif type == "namespace" then
    return data.name .. ".*"
  elseif type == "file" or type == "dir" then
    return vim.tbl_map(function(child)
      return get_filters_for_node(child)
    end, node:children())
  else
    error("unknown node type " .. type)
  end
end

local last_notified = 0

---Notifies the user that the given nodes they tried to test are not mapped to
---executables and require configuration.
---@param node_names string[]
local function notify_nodes_missing_executables(node_names)
  local now = os.time()
  if now - last_notified < 2 then
    return
  end
  last_notified = now
  vim.notify(
    string.format(
      "Some nodes do not have a corresponding GTest executable set. Please "
        .. "configure them by mraking them and then running :ConfigureGtest "
        .. "in the summary window. Nodes: %s",
      table.concat(node_names, ", ")
    ),
    vim.log.levels.ERROR
  )
end

---@class neotest-gtest.NeotestAdapter
---@field _tree neotest.Tree
---@field _extra_args string
---@field _strategy_name string
---@field _output_counter integer
local NeotestAdapter = {}
---Creates a new NeotestAdapter, which is responsible for creating neotest run
---specs
---@param args neotest.RunArgs
---@return neotest-gtest.NeotestAdapter
function NeotestAdapter:new(args)
  local adapter = {
    _tree = args.tree,
    _extra_args = args.extra_args,
    _strategy_name = args.strategy,
    _output_counter = 0,
  }
  setmetatable(adapter, self)
  self.__index = self
  return adapter
end

---Creates neotest.specs for the given args supplied to the constructor. Returns
---nil and notifies the user in case of error
---@return neotest.RunSpec[]|nil
function NeotestAdapter:build_specs()
  local executable2nodes = self:_try_group_nodes_by_executable()
  if not executable2nodes then
    return nil
  end

  local specs = {}
  for executable, nodes in pairs(executable2nodes) do
    local filters = self:_build_filters_for_nodes(nodes)
    local spec = self:_build_spec_for_executable(executable, filters)
    specs[#specs + 1] = spec
  end
  return specs
end

---@return table<string, neotest.Tree>|nil executable2nodes
---@private
function NeotestAdapter:_try_group_nodes_by_executable()
  local exe2node_ids, missing = executables.find_executables(self._tree)
  if exe2node_ids == nil then
    assert(missing, "find_executables must return nil if ok == false")
    notify_nodes_missing_executables(missing)
    return nil
  end
  assert(exe2node_ids, "find_executables must not return nil if ok == true")

  return vim.tbl_map(function(node_ids)
    return self:_get_nodes_by_ids(node_ids)
  end, exe2node_ids)
end

---@param node_ids string[]
---@return neotest.Tree[]
---@private
function NeotestAdapter:_get_nodes_by_ids(node_ids)
  return vim.tbl_map(function(node_id)
    local node = self._tree:get_key(node_id)
    return node
  end, node_ids)
end

---@param nodes neotest.Tree[]
---@return string[] filters
---@private
function NeotestAdapter:_build_filters_for_nodes(nodes)
  return vim.tbl_flatten(vim.tbl_map(function(node)
    return get_filters_for_node(node)
  end, nodes))
end

---@param executable string
---@param filters string[]
---@return neotest.RunSpec
---@private
function NeotestAdapter:_build_spec_for_executable(executable, filters)
  local results_path = utils.new_results_dir({
    history_size = config.history_size,
  }) .. "test_result_" .. self._output_counter .. ".json"

  local command = vim.tbl_flatten({
    executable,
    "--gtest_filter=" .. table.concat(filters, ":"),
    "--gtest_output=json:" .. results_path,
    -- By default disabled when redirected to a file, but we want to enable it
    -- because we preserve shell colors.
    "--gtest_color=yes",
    self._extra_args,
  })

  return {
    command = command,
    context = { results_path = results_path },
    strategy = self:_make_strategy_for_command(command),
  }
end

---@param command string[]
---@return table|nil strategy The nvim-dap strategy to be used in the specs
---@private
function NeotestAdapter:_make_strategy_for_command(command)
  if self._strategy_name ~= "dap" then
    return nil
  end

  return {
    name = "Debug with neotest-gtest",
    type = config.debug_adapter,
    request = "launch",
    program = command[1],
    args = { unpack(command, 2) },
  }
end

return NeotestAdapter
