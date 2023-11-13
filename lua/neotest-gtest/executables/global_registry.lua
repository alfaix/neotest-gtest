local utils = require("neotest-gtest.utils")
local ExecutablesRegistry = require("neotest-gtest.executables.registry")

local GlobalExecutableRegistry = {}
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

local globalRegistry = GlobalExecutableRegistry:new()

return globalRegistry
