local assert = require("luassert")
local GlobalRegistry = require("neotest-gtest.executables.global_registry")
local neotest = require("neotest")
local config = require("neotest-gtest.config")
local parse_module = require("neotest-gtest.parse")
local lib = require("neotest.lib")
local helpers = require("tests.utils.helpers")

local NeotestStateMock = {}

function NeotestStateMock:new()
  local obj = {
    _old_state = neotest.state,
    _adapter2tree = {},
  }

  setmetatable(obj, { __index = self })

  neotest.state = {
    adapter2tree = self._adapter2tree,
    adapter_ids = function()
      return vim.tbl_keys(obj._adapter2tree)
    end,
    positions = function(adapter_id)
      return obj:positions(adapter_id)
    end,
  }
  return obj
end

function NeotestStateMock:positions(_adapter_id)
  local tree = self._adapter2tree[_adapter_id]
  if tree == nil then
    error("No tree registered for adapter " .. _adapter_id)
  end
  return tree
end

function NeotestStateMock:add_tree(tree)
  local adapter_id = "neotest-gtest:" .. tree:data().path
  self._adapter2tree[adapter_id] = tree
end

function NeotestStateMock:revert()
  neotest.state = self._old_state
end

local _neotest_state = NeotestStateMock:new()

---@class neotest-gtest.MockProject
---@field _root string
---@field _tree? neotest.Tree
local MockProject = {}

---@return neotest-gtest.MockProject
function MockProject:new(root)
  if root == nil then
    root = helpers.mktempdir()
  end
  local obj = {
    _root = root,
    _tree = nil,
  }
  setmetatable(obj, { __index = self })
  return obj
end

function MockProject:root()
  return self._root
end

local function add_files_to_tree(tree, test_files)
  for _, test_file in ipairs(test_files) do
    local file_tree = parse_module.parse_positions(test_file)
    --TODO: manually implement this, I guess (it's private)
    tree = lib.positions.merge(tree, file_tree)
  end
  return tree
end

function MockProject:set_contents(fname2content)
  fname2content = fname2content or {}
  -- create a root marker
  fname2content["compile_commands.json"] = "foo"
  helpers.write_file_tree(self._root, fname2content)
  local abspaths = vim.tbl_map(function(fname)
    return self._root .. lib.files.sep .. fname
  end, vim.tbl_keys(fname2content))
  local test_files = lib.func_util.filter_list(config.is_test_file, abspaths)
  local tree = lib.files.parse_dir_from_files(self._root, test_files)
  self._tree = add_files_to_tree(tree, test_files)
  _neotest_state:add_tree(self._tree)
end

---@return neotest-gtest.ExecutablesRegistry
function MockProject:get_registry()
  return GlobalRegistry:for_dir(self._root)
end

---@return neotest.Tree
function MockProject:get_tree()
  return self._tree
end

function MockProject:set_executables(node2executable)
  node2executable = node2executable or {}
  for node, executable in pairs(node2executable) do
    node = self:prepend_root(node)
    ---@cast node string
    self:get_registry():update_executable(node, executable)
  end
end

function MockProject:assert_configured(node, exec)
  node = self:prepend_root(node)
  ---@cast node string
  local exe2node, missing = self:get_registry():find_executables(node)
  assert(missing == nil and exe2node ~= nil)
  assert.is_true(vim.tbl_contains(exe2node[exec], node))
end

function MockProject:assert_not_configured(node)
  node = self:prepend_root(node)
  ---@cast node string
  local exe2node, missing = self:get_registry():find_executables(node)
  assert.is_nil(exe2node)
  assert(missing)
  ---@cast node string
  assert.is_true(vim.startswith(missing[1], node))
end

---@param node_ids string[]
---@return string[]
---@overload fun(self: neotest-gtest.MockProject, node_ids: string): string
function MockProject:prepend_root(node_ids)
  if type(node_ids) == "string" then
    if vim.startswith(node_ids, self._root) then
      return node_ids
    else
      return string.format("%s/%s", self._root, node_ids)
    end
  end
  return vim.tbl_map(function(node)
    self:prepend_root(node)
  end, node_ids)
end

return MockProject
