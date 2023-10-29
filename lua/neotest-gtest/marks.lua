local M = {}
local executables = require("neotest-gtest.executables")

function M.set_summary_autocmd(config)
  local group = vim.api.nvim_create_augroup("NeotestGtestConfigureMarked", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "neotest-summary",
    group = group,
    callback = function(ctx)
      local buf = ctx.buf
      vim.api.nvim_buf_create_user_command(buf, "ConfigureGtest", function()
        executables.configure_executable()
      end, {})
      if config.mappings.configure ~= nil then
        vim.api.nvim_buf_set_keymap(
          buf,
          "n",
          config.mappings.configure_key,
          "<CMD>ConfigureGtest",
          { desc = "Select a Google Test executable for marked tests" }
        )
      end
    end,
  })
end

return M
