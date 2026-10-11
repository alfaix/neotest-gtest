vim.notify = print
vim.opt.swapfile = false
vim.opt.rtp:append(".")

vim.pack.add({
  "https://github.com/nvim-lua/plenary.nvim",
  "https://github.com/nvim-neotest/nvim-nio",
  "https://github.com/nvim-neotest/neotest",
  "https://github.com/mfussenegger/nvim-dap",
}, { load = true, confirm = false })

assert(vim.treesitter.language.add("cpp"), "Install the Tree-sitter CPP parser before testing")
