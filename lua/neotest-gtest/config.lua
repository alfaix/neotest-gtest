local lib = require("neotest.lib")

local M = {}

local _test_extensions = {
  ["cpp"] = true,
  ["cppm"] = true,
  ["cc"] = true,
  ["cxx"] = true,
  ["c++"] = true,
}

---Analyzes the path to determine whether the file is a C++ test file or not.
---
---Simply checks if the file fits either "test_*.ext" or "*_test.ext" pattern,
---where ext is one of the extensions in `M.test_extensions`.
---
---@param file_path string the path to analyze
---@return boolean true if `path` is a test file, false otherwise.
local function is_test_file(file_path)
  local elems = vim.split(file_path, lib.files.sep, { plain = true })
  local filename = elems[#elems]
  if filename == "" then -- directory
    return false
  end
  local extsplit = vim.split(filename, ".", { plain = true })
  local extension = extsplit[#extsplit]
  local fname_last_part = extsplit[#extsplit - 1]
  local result = _test_extensions[extension]
      and (vim.startswith(filename, "test_") or vim.endswith(fname_last_part, "_test"))
    or false
  return result
end

local default_config = {
  root = lib.files.match_root_pattern(
    "compile_commands.json",
    "compile_flags.txt",
    "WORKSPACE",
    ".clangd",
    "init.lua",
    "init.vim",
    "build",
    ".git"
  ),
  debug_adapter = "codelldb",
  is_test_file = is_test_file,
  history_size = 3,
  parsing_throttle_ms = 10,
  mappings = { configure = nil },
  summary_view = {
    header_length = 80,
    shell_palette = {
      passed = "\27[32m",
      skipped = "\27[33m",
      failed = "\27[31m",
      stop = "\27[0m",
      bold = "\27[1m",
    },
  },
  extra_args = {},
  filter_dir = function(name, rel_path, root)
    local neotest_config = require("neotest.config")
    local fn = vim.tbl_get(neotest_config, "projects", root, "discovery", "filter_dir")
    if fn ~= nil then
      return fn(name, rel_path, root)
    end
    return true
  end,
}

local config = default_config

local module_metatable = {
  __index = function(table, key)
    return config[key]
  end,
  __newindex = function(table, key, value)
    if key == "get_config" or key == "setup" or key == "reset" then
      rawset(M, key, value)
    end
    config[key] = value
  end,
}

setmetatable(M, module_metatable)

function M.setup(config_override)
  config = vim.tbl_deep_extend("force", default_config, config_override)
end

function M.get_config()
  return config
end

-- for tests
function M.reset()
  config = default_config
end

return M
