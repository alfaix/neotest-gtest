local lazypath = vim.fn.stdpath("data") .. "/lazy"

local plugins = { "plenary.nvim", "nvim-dap", "nvim-treesitter", "neotest", "nvim-nio" }

vim.notify = print
vim.opt.swapfile = false
vim.opt.rtp:append(".")
for _, plugin in ipairs(plugins) do
  vim.opt.rtp:append(lazypath .. "/" .. plugin)
end
