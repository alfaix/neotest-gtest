local tree_utils = require("tests.utils.tree")
local NeotestAdapter = require("neotest-gtest.neotest_adapter")
local assert = require("luassert")

local function tree2ids(tree)
  if #tree:children() == 0 then
    return tree:data().id
  end
  return { tree:data().id, vim.tbl_map(function(x)
    return tree2ids(x)
  end, tree:children()) }
end

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

local function assert_command_meets_spec(command, spec)
  assert.are.equal(command[1], spec.command[1])

  local args = parse_args_to_table(command)
  local spec_args = parse_args_to_table(spec.command)
  if spec.allow_extra_args then
    for k, v in pairs(spec_args) do
      assert.are.equal(v, args[k])
    end
  else
    assert.are.same(spec_args, args)
  end
end

local function assert_strategy_meets_spec(strategy, spec)
  if spec.strategy == nil then
    return nil
  end
  local command_spec = {
    { spec.expected_strategy.program, unpack(spec.expected_strategy.args) },
    allow_extra_args = spec.allow_extra_args,
  }
  local actual_command = { strategy.program, unpack(strategy.args) }
  assert_command_meets_spec(actual_command, command_spec)

  strategy.program = nil
  strategy.args = nil
  spec.expected_strategy.program = nil
  spec.expected_strategy.args = nil
  assert.are.same(strategy, spec.expected_strategy)
end

local function assert_context_contains_results_path(command, context)
  local args = parse_args_to_table(command)
  local gtest_output = args["gtest_output"]
  local results_path = gtest_output:match("^json:(.*)$")
  assert.is_not_nil(results_path)
  assert.are.same({ results_path = results_path }, context)
end

local function assert_generated_specs_match_expected(generated, spec)
  if spec.expect_error then
    assert.is_nil(generated)
  else
    assert.is_not_nil(generated)
    assert.are.equal(#spec.neotest_specs, #generated)
    for i = 1, #spec.neotest_specs do
      spec.neotest_specs[i].allow_extra_args = spec.allow_extra_args
      assert_command_meets_spec(generated[i].command, spec.neotest_specs[i])
      assert_strategy_meets_spec(generated[i].strategy, spec)
      assert_context_contains_results_path(generated[i].command, generated[i].context)
    end
  end
end

local function call_adapter_with_spec(tree, spec)
  if spec.input_tree ~= nil then
    local fpath = tree:data().path
    tree = assert(tree:get_key(fpath .. "::" .. spec.input_tree))
  end
  local adapter = NeotestAdapter:new({
    tree = tree,
    extra_args = spec.extra_args,
    strategy = spec.input_strategy,
  })
  return adapter:build_specs()
end

local function sort_by_command(tbl)
  if tbl == nil then
    return nil
  end
  local function key(lhs, rhs)
    return lhs.command[1] < rhs.command[1]
  end
  return table.sort(tbl, key)
end

local M = {}

function M.assert_specs_for_files(fname2content, spec)
  local tree = tree_utils.make_directory_tree(fname2content)
  local generated_specs = call_adapter_with_spec(tree, spec)
  sort_by_command(generated_specs)
  sort_by_command(spec.neotest_specs)
  assert_generated_specs_match_expected(generated_specs, spec)
end

function M.assert_spec_for_file(contents, single_file_spec)
  local tree = tree_utils.parse_tree_from_string(contents)
  local full_spec = {
    neotest_specs = { single_file_spec },
    input_strategy = single_file_spec.input_strategy,
    input_tree = single_file_spec.input_tree,
    strategy = single_file_spec.strategy,
    expect_error = single_file_spec.expect_error,
    extra_args = single_file_spec.extra_args,
    allow_extra_args = single_file_spec.allow_extra_args,
  }
  local generated_specs = call_adapter_with_spec(tree, full_spec)
  assert_generated_specs_match_expected(generated_specs, full_spec)
end

return M
