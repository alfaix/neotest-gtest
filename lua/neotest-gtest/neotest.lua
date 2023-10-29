local executables = require("neotest-gtest.executables")
local utils = require("neotest-gtest.utils")
local config = require("neotest-gtest.config")

local M = {}

function M.build_commands_for_tree(tree, extra_args)
  local tree = args.tree
  local path = tree:data().path
  local root = utils.normalize_path(config.get_config().root(path))
end

return M
