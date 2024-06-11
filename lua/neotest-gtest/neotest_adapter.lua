local lib = require("neotest.lib")
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
    utils.schedule_error("TEST_P is not yet supported, sorry :(")
  else
    local parts = vim.split(posid, "::", { plain = true })
    -- file::namespace::test_name
    assert(#parts == 3, "bad node")
    local namespace = parts[2]
    local test_name = parts[3]
    return string.format("%s.%s", namespace, test_name)
  end
end

local function get_filters_for_nodes(nodes)
  local function node2filter(node)
    local type = node:data().type
    if type == "test" then
      return get_filter_for_test_node(node)
    elseif type == "namespace" then
      return node:data().name .. ".*"
    else
      utils.schedule_error("unknown node type " .. type)
    end
  end
  return vim.tbl_map(node2filter, nodes)
end

---@param nodes neotest.Tree[]
---@return neotest.Tree[]
local flatten_nodes = function(nodes)
  local result = {}
  local function recurse(node)
    if type(node) == "table" then
      if node[1] ~= nil then
        for _, child in ipairs(node) do
          recurse(child)
        end
      elseif not vim.tbl_isempty(node) then
        result[#result + 1] = node
      end
    else
      result[#result + 1] = node
    end
  end
  recurse(nodes)
  return result
end

---Returns a list of nodes which can be filtered by (i.e., namespaces and tests)
---@param nodes neotest.Tree[] position to create a filter to. Assumed to be
---non-overlapping
---@return neotest.Tree | neotest.Tree[] filters
local function get_filterable_nodes(nodes)
  local function recurse(node)
    local data = node:data()
    local type = data.type

    if type == "file" or type == "dir" then
      return vim.tbl_map(function(child)
        return recurse(child)
      end, node:children())
    elseif type == "test" or type == "namespace" then
      return node
    else
      utils.schedule_error("unknown node type " .. type)
    end
  end
  return flatten_nodes(vim.tbl_map(recurse, nodes))
end

local last_notified = 0

---Notifies the user that the given nodes they tried to test are not mapped to
---executables and require configuration.
---@param node_names string[]
local function _raise_nodes_missing_executables(node_names)
  local now = os.time()
  if now - last_notified < 2 then
    return
  end
  last_notified = now
  utils.schedule_error(
    string.format(
      "Some nodes do not have a corresponding GTest executable set. Please "
        .. "configure them by marking them and then running :ConfigureGtest "
        .. "in the summary window. Nodes: %s",
      table.concat(node_names, ", ")
    )
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

  local specs = {}
  for executable, nodes in pairs(executable2nodes) do
    local spec = self:_build_spec_for_executable(executable, nodes)
    specs[#specs + 1] = spec
  end
  return specs
end

---@return table<string, neotest.Tree> executable2nodes
---@private
function NeotestAdapter:_try_group_nodes_by_executable()
  local exe2node_ids, missing = executables.find_executables(self._tree)
  if exe2node_ids == nil then
    assert(missing, "find_executables must return nil if ok == false")
    _raise_nodes_missing_executables(missing)
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

---@param executable string
---@param nodes neotest.Tree[]
---@return neotest.RunSpec
---@private
function NeotestAdapter:_build_spec_for_executable(executable, nodes)
  nodes = get_filterable_nodes(nodes)
  local filters = get_filters_for_nodes(nodes)
  local results_path = utils.new_results_dir({
    history_size = config.history_size,
  }) .. "/test_result_" .. self._output_counter .. ".json"

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
    cwd = utils.normalized_root(vim.loop.cwd()),
    command = command,
    context = {
      results_path = results_path,
      name2path = self:_map_names_to_paths(nodes),
    },
    strategy = self:_make_strategy_for_command(command),
  }
end

---@param nodes neotest.Tree[]
---@return table<string, string>
---@private
function NeotestAdapter:_map_names_to_paths(nodes)
  local name2path = {}
  for _, node in ipairs(nodes) do
    local data = node:data()
    if data.type == "test" then
      local ns_name = node:parent():data().name
      name2path[ns_name .. "." .. data.name] = data.path
    elseif data.type == "namespace" then
      name2path[data.name] = data.path
    else
      utils.schedule_error("unknown node type " .. type)
    end
  end
  return name2path
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
