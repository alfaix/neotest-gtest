local MockProject = require("tests.utils.mock_project")
local utils = require("neotest-gtest.utils")
local NeotestAdapter = require("neotest-gtest.neotest_adapter")
local assert = require("luassert")

local function sort_filters_arg(filters_arg)
  local filters = vim.split(filters_arg, ":", { plain = true })
  table.sort(filters)
  return table.concat(filters, ":")
end

local function parse_args_to_table(command)
  local args_list = vim.list_slice(command, 2)
  local args = {}
  for _, arg in ipairs(args_list) do
    local arg_name, arg_value = arg:match("^%-%-(.*)=(.*)$")
    if arg_name and arg_value then
      if arg_name == "gtest_filter" then
        arg_value = sort_filters_arg(arg_value)
      end
      args[arg_name] = arg_value
    else
      args[#args + 1] = arg
    end
  end
  return args
end

local function sort_by_keys(tbl, ...)
  if tbl == nil then
    return nil
  end
  local args = { ... }
  local function key(lhs, rhs)
    return vim.tbl_get(lhs, unpack(args)) < vim.tbl_get(rhs, unpack(args))
  end
  table.sort(tbl, key)
end

local function filter2testnames(filters)
  local positions = {}
  for _, filter in ipairs(filters) do
    local parts = vim.split(filter, ".", { plain = true })
    local namespace = parts[1]
    local test_name = parts[2]
    if test_name == "*" then
      positions[#positions + 1] = namespace
    else
      positions[#positions + 1] = namespace .. "::" .. test_name
    end
  end
  return positions
end

---@class neotest-gtest.AdapterResultSpec
---@field commands string[][]
---@field input_strategy string
---@field input_key string
---@field strategy table
---@field expect_error boolean
---@field extra_args table
---@field allow_extra_args boolean
---@field expected_strategy table
local AdapterResultSpec = {}

---@return neotest-gtest.AdapterResultSpec
function AdapterResultSpec:new(opts)
  local obj = utils.tbl_copy(opts)
  sort_by_keys(opts.commandsm, 1)
  setmetatable(obj, { __index = self })
  return obj
end

---@return neotest-gtest.AdapterResultSpec
function AdapterResultSpec:from_single_file_spec(opts, filename)
  if opts.input_key == nil then
    opts.input_key = filename
  else
    opts.input_key = filename .. "::" .. opts.input_key
  end
  opts.commands = { opts.command }
  opts.command = nil
  return AdapterResultSpec:new(opts)
end

---@param project neotest-gtest.MockProject
function AdapterResultSpec:assert_matches_project(project)
  self._project = project
  local error
  error, self._neotest_specs = self:_call_adapter()
  if self.expect_error then
    assert.is_not_nil(error)
  else
    assert.is_nil(error)
    self:_check_specs()
  end
end

function AdapterResultSpec:_call_adapter()
  local tree = self._project:get_tree()
  local root = self._project:root()
  if self.input_key ~= nil then
    local full_key = root .. "/" .. self.input_key
    tree = assert(tree:get_key(full_key))
  end
  local adapter = NeotestAdapter:new({
    tree = tree,
    extra_args = self.extra_args,
    strategy = self.input_strategy,
  })
  local ok, specs_or_error = pcall(adapter.build_specs, adapter)
  if ok then
    sort_by_keys(specs_or_error, "command", 1)
    return nil, specs_or_error
  else
    return specs_or_error, nil
  end
end

function AdapterResultSpec:_check_specs()
  assert.is_not_nil(self._neotest_specs)
  assert.are.equal(#self.commands, #self._neotest_specs)
  for i = 1, #self.commands do
    local actual_command = self._neotest_specs[i].command
    local expected_command = self.commands[i]
    self:_check_command(expected_command, actual_command)
    self:_check_strategy(self._neotest_specs[i].strategy)
    self:_check_context_matches_command(self._neotest_specs[i].context, actual_command)
  end
end

function AdapterResultSpec:_check_command(expected_command, actual_command)
  assert.are.equal(expected_command[1], actual_command[1])

  local actual_args = parse_args_to_table(actual_command)
  local expected_args = parse_args_to_table(expected_command)
  if self.allow_extra_args then
    for k, v in pairs(expected_args) do
      assert.are.equal(v, actual_args[k])
    end
  else
    assert.are.same(expected_args, actual_args)
  end
end

function AdapterResultSpec:_check_strategy(strategy)
  if self.expected_strategy == nil then
    return nil
  end
  local expected_command = { self.expected_strategy.program, unpack(self.expected_strategy.args) }
  local actual_command = { strategy.program, unpack(strategy.args) }
  self:_check_command(expected_command, actual_command)

  strategy.program = nil
  strategy.args = nil
  self.expected_strategy.program = nil
  self.expected_strategy.args = nil
  assert.are.same(strategy, self.expected_strategy)
end

function AdapterResultSpec:_check_context_matches_command(context, command)
  local args = parse_args_to_table(command)
  local gtest_output = args["gtest_output"]
  local results_path = gtest_output:match("^json:(.*)$")
  local filter_arg = args["gtest_filter"]
  local expected_positions = self:_filter_arg2positions(filter_arg)

  assert.is_not_nil(results_path)
  assert.is_not_nil(context.positions)
  table.sort(context.positions)
  table.sort(expected_positions)
  assert.are.same({ results_path = results_path, positions = expected_positions }, context)
end

function AdapterResultSpec:_filter_arg2positions(filters)
  filters = vim.split(filters, ":", { plain = true })
  local testnames = filter2testnames(filters)
  local testnames2positions = self:_get_testnames2positions()
  local positions = {}
  for _, testname in ipairs(testnames) do
    assert.is_not_nil(testnames2positions[testname])
    positions[#positions + 1] = testnames2positions[testname]
  end
  return positions
end

function AdapterResultSpec:_get_testnames2positions()
  local testnames2positions = {}
  for _, file in ipairs(self._project:get_tree():children()) do
    local filepath = file:data().id
    for _, namespace in ipairs(file:children()) do
      local ns_name = namespace:data().name
      testnames2positions[ns_name] = filepath .. "::" .. ns_name
      for _, test in ipairs(namespace:children()) do
        local full_id = ns_name .. "::" .. test:data().name
        testnames2positions[full_id] = filepath .. "::" .. full_id
      end
    end
  end
  return testnames2positions
end

local M = {}

function M.assert_specs_for_files(fname2content, spec)
  local project = MockProject:new()
  project:set_contents(fname2content)
  local adapter_specs = AdapterResultSpec:new(spec)
  adapter_specs:assert_matches_project(project)
end

function M.assert_spec_for_file(contents, single_file_spec)
  local project = MockProject:new()
  project:set_contents({ ["test_f.cpp"] = contents })
  local adapter_spec = AdapterResultSpec:from_single_file_spec(single_file_spec, "test_f.cpp")
  adapter_spec:assert_matches_project(project)
end

return M
