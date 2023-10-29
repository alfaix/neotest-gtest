local lib = require("neotest.lib")
local utils = require("neotest-gtest.utils")

local M = {}

local default_config = {
  debug_adapter = "codelldb",
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
  history_size = 3,
  is_test_file = utils.is_test_file,
  mappings = { configure = nil },
  filter_dir = function(name, rel_path, root)
    return true
  end,
}

local config = default_config

setmetatable(M, { __index = config })

function M.setup(config_override)
  config = vim.tbl_deep_extend("force", config, config_override)
  setmetatable(M, { __index = config })
end

-- for tests
function M.reset()
  config = default_config
end

return M
