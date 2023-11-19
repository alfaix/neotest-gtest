local GlobalRegistry = require("neotest-gtest.executables.global_registry")
local ui = require("neotest-gtest.executables.ui")
local config = require("neotest-gtest.config")

local M = {}

---@param node neotest.Tree Test node to perform the lookup for.
---@return {string: string[]} | nil results executable path -> node_ids[]
---@return neotest.Tree[] | nil not_found List of nodes for which no executables
---        could be found (potentially incomplete)
function M.find_executables(node)
  local tree_root = node:root()
  local registry = GlobalRegistry:for_dir(tree_root:data().path)
  return registry:find_executables(node:data().id)
end

M.configure_executable = ui.configure_executable

function M.set_summary_autocmd()
  local group = vim.api.nvim_create_augroup("NeotestGtestConfigureMarked", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "neotest-summary",
    group = group,
    callback = function(ctx)
      local buf = ctx.buf
      vim.api.nvim_buf_create_user_command(buf, "ConfigureGtest", function()
        M.configure_executable()
      end, {})
      if config.mappings.configure ~= nil then
        vim.api.nvim_buf_set_keymap(
          buf,
          "n",
          config.mappings.configure,
          "<CMD>ConfigureGtest<CR>",
          { desc = "Select a Google Test executable for marked tests" }
        )
      end
    end,
  })
end

return M
