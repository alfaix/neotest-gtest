local lazypath = vim.fn.stdpath("data") .. "/lazy"

local plugins = { "plenary.nvim", "nvim-dap", "nvim-treesitter", "neotest", "nvim-nio" }

vim.notify = print
vim.opt.swapfile = false
vim.opt.rtp:append(".")
for _, plugin in ipairs(plugins) do
  local plugin_path = lazypath .. "/" .. plugin
  vim.opt.rtp:append(plugin_path)
  package.path = package.path
    .. ";"
    .. plugin_path
    .. "/lua/?.lua"
    .. ";"
    .. plugin_path
    .. "/lua/?/init.lua"
end
