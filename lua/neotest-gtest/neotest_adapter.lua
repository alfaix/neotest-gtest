local lib = require("neotest.lib")
local executables = require("neotest-gtest.executables")
local utils = require("neotest-gtest.utils")
local config = require("neotest-gtest.config")
local test_kinds = require("neotest-gtest.test_kinds")

---Gets a filter argument for the given test node
---@param node neotest.Tree a tree node representing a test
---@return string filter Google Test filter string for the test
local function get_filter_for_test_node(node)
  local data = node:data()
  if data.extra and data.extra.runtime_name then
    return data.extra.runtime_name
  end
  local posid = data.id
  local test_kind = data.extra.kind

  if test_kind == "TYPED_TEST" or test_kind == "TYPED_TEST_P" then
    local children = node:children()
    if #children > 0 then
      return table.concat(
        vim.tbl_map(function(child)
          return child:data().extra.runtime_name
        end, children),
        ":"
      )
    end

    local namespace = node:parent():data().name
    local test_name = data.name
    if test_kind == "TYPED_TEST_P" then
      return string.format("*/%s/*.%s:%s/*.%s", namespace, test_name, namespace, test_name)
    end

    return string.format("%s/*.%s", namespace, test_name)
  end

  if test_kind == "TEST_P" then
    local namespace = node:parent():data().name
    local test_name = data.name
    return string.format("*/%s.%s/*:%s.%s/*", namespace, test_name, namespace, test_name)
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
      local namespace = node:data().name
      local filters = { namespace .. ".*" }
      for _, child in ipairs(node:children()) do
        local kind = child:data().extra.kind
        if test_kinds.is_generated(kind) then
          filters[#filters + 1] = get_filter_for_test_node(child)
        end
      end
      return table.concat(filters, ":")
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

local throttle_ms = 300
local last_fired = { raise = 0, warn = 0 }

local function throttled(kind)
  local now = vim.uv.now()
  if now - last_fired[kind] < throttle_ms then
    return true
  end
  last_fired[kind] = now
  return false
end

---Notifies the user that the given nodes they tried to test are not mapped to
---executables and require configuration.
---@param node_names string[]
local function _raise_nodes_missing_executables(node_names)
  if throttled("raise") then
    return
  end
  utils.schedule_error(
    string.format(
      "Some nodes do not have a corresponding GTest executable set. Please "
        .. "configure them by marking them and then running :ConfigureGtest "
        .. "in the summary window. Nodes: %s",
      table.concat(node_names, ", ")
    )
  )
end

local function _warn_nodes_missing_executables(node_names)
  if throttled("warn") then
    return
  end
  utils.schedule_notify(
    string.format("Nodes missing executable: %s", table.concat(node_names, ", ")),
    vim.log.levels.WARN
  )
end

---@class neotest-gtest.NeotestAdapter
---@field _tree neotest.Tree
---@field _extra_args string|string[]
---@field _strategy_name string
---@field _output_counter integer
---@field _process_isolation boolean
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
    _process_isolation = args.process_isolation == nil and config.process_isolation
      or args.process_isolation,
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

  if self._process_isolation and self._strategy_name ~= "dap" then
    return self:_build_isolated_specs(executable2nodes)
  end

  local specs = {}
  for executable, nodes in pairs(executable2nodes) do
    local spec = self:_build_spec_for_executable(executable, nodes)
    specs[#specs + 1] = spec
  end
  return specs
end

---@param executable2nodes table<string, neotest.Tree[]>
---@return neotest.RunSpec[]
function NeotestAdapter:_build_isolated_specs(executable2nodes)
  local cases = {}
  local seen = {}
  local results_dir

  local function add_cases(executable, node)
    local data = node:data()

    if data.type == "test" then
      local children = node:children()
      local kind = data.extra and data.extra.kind
      local generated = test_kinds.is_generated(kind)

      if generated and #children == 0 and not (data.extra and data.extra.runtime_name) then
        error("Process isolation requires compiled case inventory for " .. data.id)
      end

      if #children == 0 then
        if not seen[data.id] then
          seen[data.id] = true
          results_dir = results_dir
            or utils.new_results_dir({
              history_size = config.history_size,
            })
          cases[#cases + 1] = self:_build_spec_for_executable(executable, { node }, results_dir)
        end
        return
      end
    end

    for _, child in ipairs(node:children()) do
      add_cases(executable, child)
    end
  end

  for executable, nodes in pairs(executable2nodes) do
    for _, node in ipairs(nodes) do
      add_cases(executable, node)
    end
  end

  if #cases == 0 then
    return {}
  end

  table.sort(cases, function(left, right)
    return left.context.position_ids[1] < right.context.position_ids[1]
  end)

  return {
    {
      cwd = utils.normalized_root(vim.loop.cwd()),
      command = cases[1].command,
      context = { isolated_cases = cases },
      strategy = require("neotest-gtest.isolation").strategy,
    },
  }
end

---@return table<string, neotest.Tree> executable2nodes
---@private
function NeotestAdapter:_try_group_nodes_by_executable()
  local exe2node_ids, missing = executables.find_executables(self._tree)
  if #missing > 0 then
    if next(exe2node_ids) == nil then
      _raise_nodes_missing_executables(missing)
    end
    _warn_nodes_missing_executables(missing)
  end

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
---@param results_dir? string
---@return neotest.RunSpec
---@private
function NeotestAdapter:_build_spec_for_executable(executable, nodes, results_dir)
  nodes = get_filterable_nodes(nodes)
  local filters = get_filters_for_nodes(nodes)
  results_dir = results_dir or utils.new_results_dir({
    history_size = config.history_size,
  })
  local results_path = results_dir .. "/test_result_" .. self._output_counter .. ".json"
  self._output_counter = self._output_counter + 1

  local command = vim
    .iter({
      executable,
      "--gtest_filter=" .. table.concat(filters, ":"),
      "--gtest_output=json:" .. results_path,
      -- By default disabled when redirected to a file, but we want to enable it
      -- because we preserve shell colors.
      "--gtest_color=yes",
      self._extra_args,
    })
    :flatten(math.huge)
    :totable()

  return {
    cwd = utils.normalized_root(vim.loop.cwd()),
    command = command,
    context = {
      results_path = results_path,
      name2path = self:_map_names_to_paths(nodes),
      position_ids = vim.tbl_map(function(node)
        return node:data().id
      end, nodes),
    },
    strategy = self:_make_strategy_for_command(command),
  }
end

---@param nodes neotest.Tree[]
---@return table<string, string>
---@private
function NeotestAdapter:_map_names_to_paths(nodes)
  local name2path = {}
  local function map_name(name, path, strict)
    if strict then
      assert(
        name2path[name] == nil or name2path[name] == path,
        "Conflicting executable mappings for " .. name
      )
    end
    name2path[name] = path
  end
  local function map_runtime(node)
    for _, child in ipairs(node:children()) do
      if child:data().extra and child:data().extra.runtime_name then
        map_name(child:data().extra.runtime_name, child:data().path, true)
      end
      map_runtime(child)
    end
  end
  for _, node in ipairs(nodes) do
    local data = node:data()
    if data.type == "test" then
      if data.extra and data.extra.runtime_name then
        local source = node:parent()
        local ns_name = source:parent():data().name
        map_name(ns_name .. "." .. source:data().name, data.path)
        map_name(data.extra.runtime_name, data.path, true)
      else
        local ns_name = node:parent():data().name
        map_name(ns_name .. "." .. data.name, data.path)
      end
    elseif data.type == "namespace" then
      map_name(data.name, data.path)
    else
      utils.schedule_error("unknown node type " .. type)
    end
    map_runtime(node)
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

function NeotestAdapter._reset_throttle()
  last_fired = { raise = 0, warn = 0 }
end

return NeotestAdapter
