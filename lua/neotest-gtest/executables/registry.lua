local Storage = require("neotest-gtest.storage")
local utils = require("neotest-gtest.utils")
local lib = require("neotest.lib")
local neotest = require("neotest")

local ADAPTER_PREFIX = "neotest-gtest:"

local function _is_ancestor(ancestor, child)
  local is_prefix = vim.startswith(child, ancestor)
  if is_prefix then
    return (
      child:sub(#ancestor + 1, #ancestor + 1) == lib.files.sep
      or child:sub(#ancestor + 1, #ancestor + 2) == "::"
    )
  else
    return false
  end
end

---@param groups table<string, string[]>[]
local function _merge_node_by_executable_groups(groups)
  local exe2nodes = {}
  for _, group in ipairs(groups) do
    for exe, nodes in pairs(group) do
      if exe2nodes[exe] == nil then
        exe2nodes[exe] = {}
      end
      for _, node in ipairs(nodes) do
        exe2nodes[exe][#exe2nodes[exe] + 1] = node
      end
    end
  end
  return exe2nodes
end

---@class neotest-gtest.ExecutablesRegistry
---@field _root_dir string
---@field _storage neotest-gtest.Storage
---@field _node2executable table<string, string>
---@field _tree neotest.Tree
local ExecutablesRegistry = {}

---@return neotest-gtest.ExecutablesRegistry
function ExecutablesRegistry:new(normalized_root_dir)
  local storage, _ = Storage:for_directory(normalized_root_dir)
  local registry = {
    _root_dir = normalized_root_dir,
    _storage = storage,
    _node2executable = storage:node2executable(),
    _tree = nil,
  }

  setmetatable(registry, { __index = self })
  return registry
end

---@return string[]
function ExecutablesRegistry:list_executables()
  local executables = vim.tbl_values(self._node2executable)
  local executables_set = utils.list_to_set(executables)
  return vim.tbl_keys(executables_set)
end

---@param id string
function ExecutablesRegistry:find_executables(id)
  self:_reload_tree()
  self:_ensure_node_within_root(id)
  local exe = self._node2executable[id] or self:_lookup_ancestor_executable(id)
  if exe ~= nil then
    return { [exe] = { id } }, nil
  end

  return self:_group_children_by_executable(id)
end

function ExecutablesRegistry:_reload_tree()
  local adapter_id = ADAPTER_PREFIX .. self._root_dir
  local tree = neotest.state.positions(adapter_id)
  if tree == nil then
    error("tree with root " .. self._root_dir .. " not found")
  end
  self._tree = tree
end

function ExecutablesRegistry:_lookup_ancestor_executable(id)
  for ancestor in self:_iter_ancestors(id) do
    local exe = self._node2executable[ancestor]
    if exe ~= nil then
      return exe
    end
  end
end

function ExecutablesRegistry:_group_children_by_executable(id)
  local children_exe2nodes = {}

  for child_id in self:_iter_children(id) do
    local child_exe2nodes, missing = self:_group_tree_by_executable(child_id)
    if child_exe2nodes == nil then
      return nil, missing
    end
    children_exe2nodes[#children_exe2nodes + 1] = child_exe2nodes
  end

  if #children_exe2nodes == 0 then
    -- No children then this is a leaf for which there is no executable
    return nil, { id }
  end

  return _merge_node_by_executable_groups(children_exe2nodes)
end

function ExecutablesRegistry:_group_tree_by_executable(id)
  if self._node2executable[id] ~= nil then
    return { [self._node2executable[id]] = { id } }, nil
  else
    return self:_group_children_by_executable(id)
  end
end

---Sets executable for node identified by `node_id`
---@param node_id string
---@param executable string|nil
function ExecutablesRegistry:update_executable(node_id, executable)
  self:_ensure_node_within_root(node_id)
  self:_reload_tree()
  self._node2executable[node_id] = executable
  self:_restore_invariant(node_id)
  self._storage:flush()
end

function ExecutablesRegistry:_iter_children(node_id)
  -- TODO: keep a root tree cached
  local node = self._tree:get_key(node_id)
  if node == nil then
    error(string.format("tree %s does not contain node_id %s", self._tree:data().id, node_id))
  end
  local children = node:children()

  return utils.map_list(function(child)
    return child:data().id
  end, children)
end

function ExecutablesRegistry:_iter_ancestors(node_id)
  return function(_, x)
    return self:_parent_id(x)
  end, nil, node_id
end

---Restores the following invariant: for any path root -> leaf containing
---node_id, the path contains at most one unique executable
---@param node_id string
function ExecutablesRegistry:_restore_invariant(node_id)
  local executable = self._node2executable[node_id]
  self:_clear_children_executables(node_id)
  if executable ~= nil then
    self:_sift_down_executable(node_id)
  end
end

function ExecutablesRegistry:_clear_children_executables(ancestor)
  for node, _ in pairs(self._node2executable) do
    if _is_ancestor(ancestor, node) then
      self._node2executable[node] = nil
    end
  end
end

function ExecutablesRegistry:_sift_down_executable(node_id)
  local my_executable = self._node2executable[node_id]
  local configured_ancestor, parent_executable = self:_find_ancestor_with_executable(node_id)

  if parent_executable == my_executable then
    self._node2executable[node_id] = nil -- avoid duplicates, prefer parent configuration
  elseif parent_executable ~= nil then
    self:_sift_down_executable_from_parent(node_id, configured_ancestor)
  end
end

function ExecutablesRegistry:_sift_down_executable_from_parent(node_id, configured_ancestor)
  local ancestor_executable = self._node2executable[configured_ancestor]
  local ancestors = utils.collect_iterable(self:_iter_ancestors(node_id))
  local ancesotrs_set = utils.list_to_set(ancestors)

  for _, ancestor in ipairs(ancestors) do
    for sibling in self:_iter_children(ancestor) do
      if not ancesotrs_set[sibling] and sibling ~= node_id then
        self._node2executable[sibling] = ancestor_executable
      end
    end

    self._node2executable[ancestor] = nil
    if ancestor == configured_ancestor then
      break
    end
  end
end

function ExecutablesRegistry:_find_ancestor_with_executable(node_id)
  for ancestor in self:_iter_ancestors(node_id) do
    if self._node2executable[ancestor] ~= nil then
      return ancestor, self._node2executable[ancestor]
    end
  end
end

function ExecutablesRegistry:_parent_id(node_id)
  if node_id == self._root_dir then
    return nil
  end

  local parent_id = node_id:match("^(.*)%:%:[^:]+$")
  if parent_id == nil then
    parent_id = vim.fn.fnamemodify(node_id, ":h")
  end

  return parent_id
end

function ExecutablesRegistry:_ensure_node_within_root(node_id)
  if not vim.startswith(node_id, self._root_dir) then
    error(string.format("Node %s is not within root %s", node_id, self._root_dir))
  end
end

return ExecutablesRegistry
