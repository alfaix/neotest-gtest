local utils = require("neotest-gtest.utils")
local ExecutablesRegistry = require("neotest-gtest.executables.registry")

---@class neotest-gtest.GlobalExecutableRegistry
---@field _root2registry table<string, neotest-gtest.ExecutablesRegistry>
local GlobalExecutableRegistry = {}

---@private
---@return neotest-gtest.GlobalExecutableRegistry
function GlobalExecutableRegistry:new()
  local registry = {
    _root2registry = {},
  }
  setmetatable(registry, { __index = self })
  return registry
end

---@param _root_dir string
---@return neotest-gtest.ExecutablesRegistry
function GlobalExecutableRegistry:for_dir(_root_dir)
  local normalized = utils.normalize_path(_root_dir)
  if self._root2registry[normalized] == nil then
    self._root2registry[normalized] = ExecutablesRegistry:new(normalized)
  end
  return self._root2registry[normalized]
end

function GlobalExecutableRegistry:list_executables(root_dirs)
  local executables = {}
  for _, root in ipairs(root_dirs) do
    local normalized = utils.normalize_path(root)
    local registry = self:for_dir(normalized)
    for _, exe in pairs(registry:list_executables()) do
      executables[exe] = true
    end
  end
  return vim.tbl_keys(executables)
end

---intended for tests only
function GlobalExecutableRegistry:clear()
  self._root2registry = {}
end

local globalRegistry = GlobalExecutableRegistry:new()

return globalRegistry
