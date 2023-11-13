local utils = require("neotest-gtest.utils")

local M = {}

local _root2state = {}

---@param root string Directory for which to fetch the cache.
---@return neotest-gtest.Cache # Cache for the root directory.
local function get_cache(root)
  local cache, _ = Cache:cache_for(root)
  return cache
end

---Returns map node_id -> executable for root_dir root.
---@param root string Which dir to return the mapping for.
---@return {[string]: string} map Registered node_id -> executable path mappings.
local function _nodeid2exec(root)
  return get_cache(root):data().node2exec
end

local function position_path(position)
  return vim.split(position, "::")[1]
end

---Get root of a node with position_id `position`.
---@param position string Position id to fetch root directory of.
---@return string root Root directory of the test with the given position id.
local function position_root(position)
  local path = position_path(position)
  local root = require("neotest-gtest").root(path)
  return utils.normalize_path(root)
end

---Set `path` as the executable path for all given `positions`. Flushes the data
---to disk, if necessary.
---@param path nil | string Set all positions to the given path. If nil, will
---remove the mappings for the given position. This is necessary functionality
---because if a root directory is mapped to something, then its children cannot
---be assigned anything.
---@param positions string[] List of position ids to set the executable path for.
local function set_executable_for_positions(path, positions)
  ---@type table<string, neotest-gtest.Cache>
  local caches = {}

  for _, position in ipairs(positions) do
    local root = position_root(position)
    local cache = get_cache(root)
    cache:update(position, path)
    caches[root] = cache
  end

  for _, cache in pairs(caches) do
    cache:flush(false, false)
  end
end

---Looks up executable assigned to the node or any of its parents.
---@param node neotest.Tree The node for which to perform the lookup.
---@param state {[string]: string} Cached node_id -> executable path mappings.
---@param lookup_parents boolean Should we look up parents or jus this node?
---@return string | nil executable_path Executable path, if found.
local function lookup_node(node, state, lookup_parents)
  local node_id = node:data().id
  local exec = state[node_id]
  if exec ~= nil then
    return exec
  end
  if lookup_parents then
    local parent = node:parent()
    if parent ~= nil then
      return lookup_node(parent, state, true)
    end
  end
  return nil
end

---@param node neotest.Tree Test node to perform the lookup for.
---@param state {[string]: string} node_id -> executable path cache.
---@param result {[string]: string[]} executable -> list of IDs.
---@return boolean ok Whether an executable is found for all tests in the node.
---@return neotest.Tree[] | nil not_found Potentially nested list of nodes for
---which no executable could be found.
local function find_executables_recurse(node, state, result, lookup_parents)
  local executable = lookup_node(node, state, lookup_parents)
  if executable ~= nil then
    if result[executable] == nil then
      result[executable] = { node:data().id }
    else
      result[executable][#result[executable] + 1] = node:data().id
    end
    return true, nil
  end

  local node_type = node:data().type
  if node_type == "test" then
    return false, node
  end

  local all_ok = true
  local not_found = {}
  for _, child in ipairs(node:children()) do
    local ok, missing = find_executables_recurse(child, state, result, false)
    if not ok then
      assert(missing, "not ok but nothing missing")
      not_found[#not_found + 1] = missing
    end
  end
  return all_ok, not_found
end

local root2registry = {}

---Looks up a list of executables that together can run all tests under `node`.
---@param node neotest.Tree Test node to perform the lookup for.
---@return boolean ok Whether executables are found for all tests under `node`.
---@return {string: string[]} | nil results executable path -> node_ids[]
---@return neotest.Tree[] | nil not_found List of nodes for which no executables
---        could be found
function M.find_executables(node, root)
  local result = {}
  local ok, missing = find_executables_recurse(node, _nodeid2exec(root), result, true)
  if not ok then
    assert(missing, "not ok but nothing missing")
    return ok, nil, vim.tbl_flatten(missing)
  end
  return ok, result, nil
end

---Lists all executables that are registered for at least one of node in a tree
---under any of `roots`.
local function list_executables(roots)
  if type(roots) == "string" then
    roots = { roots }
  end
  local executables = {}
  for _, root in ipairs(roots) do
    for _, executable in pairs(_nodeid2exec(root)) do
      executables[executable] = true
    end
  end
  return vim.tbl_keys(executables)
end

---Prompts the user to enter executable path and sets it for all `positions`.
---@param positions string[] forwarded to `set_all`
local function input_executable(positions)
  vim.ui.input({
    prompt = "Enter path to the executable which will run marked tests: ",
    completion = "file",
  }, function(path)
    if path ~= nil then
      set_executable_for_positions(path, positions)
    end
  end)
end

local function get_marked_positions()
  local summary = require("neotest").summary
  local positions = {}
  local prefix = "neotest-gtest:"
  for adapter, marked in pairs(summary.marked()) do
    if vim.startswith(adapter, prefix) then
      for _, position in pairs(marked) do
        positions[#positions + 1] = position
      end
    end
  end
  return positions
end

---Prompts the user to configure executable for all currently marked nodes.
---Asks the user to choose an existing executable, enter a new path, or clear
---the mapping for all marked nodes.
---@see neotest.consumers.summary.marked
function M.configure_executable()
  local positions = get_marked_positions()
  if #positions == 0 then
    vim.notify(
      "Please mark the tests (or namespaces, files, dirs) first and then call :ConfigureGtest",
      vim.log.levels.INFO
    )
    return
  end
  local roots = vim.tbl_map(position_root, positions)

  local choices = list_executables(roots)
  choices[#choices + 1] = "Remove bindings for selected nodes"
  choices[#choices + 1] = "Enter path..."
  vim.ui.select(choices, {
    prompt = "Select path to the executable which will run marked tests:",
  }, function(chosen, idx)
    if idx < #choices - 1 then
      set_executable_for_positions(chosen, positions)
    elseif idx == #choices - 1 then -- choice == Remove bindings
      set_executable_for_positions(nil, positions)
    else -- choice == Enter path...
      input_executable(positions)
    end
  end)
  summary.clear_marked({ adapter = "neotest-gtest" })
end

return M
