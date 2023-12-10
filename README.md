# neotest-gtest

This is a [neotest] adapter for [Google Test][google-test], a popular C++ testing
library. It allows easy interactions with tests from your neovim.
It should work well out-of-the-box for most cases, though some features (see below)
are not yet supported.

## Features

The plugin provides full support of all neotest features:

- running tests inside NeoVim
- seeing pretty output
- debugging tests
- all other niceties of neotest

There are two major features which are not yet supported:

- `TEST_P` (parameterized tests)
- Build tool integration for recompilation - you have to do that manually (or with
  some other plugin) for now

Contributions are welcome! :)

## Installation

Use your favorite package manager. Don't forget to install [neotest] itself, which
also has a couple dependencies. The plugin also depends on `plenary.nvim`, chances
are that so do your other plugins.

For **debugging**, you also need [nvim-dap], and a debug adapter ([codelldb] is
recommended), you can install it manually or with [mason.nvim].
For setting it up, see [nvim-dap wiki][nvim-dap-wiki].

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
-- best to add to dependencies of `neotest`:
{
    "nvim-neotest/neotest",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "alfaix/neotest-gtest"
        -- your other adapters here
    }
}
```

## Usage

Simply add `neotest-gtest` to the `adapters` field of neotest's config:

```lua
require("neotest").setup({
  adapters = {
    require("neotest-gtest").setup({})
  }
})
```

**Before running tests**, you need to assign them to executables. For that, navigate
to the neotest summary window (`neotest.summary.open()`), mark the tests you want
to run (`m` by default), and run `:ConfigureGtest` in that same window. It will prompt
you to enter the path to the executable. You can set the executable path only for
parent directory, no need to set it for each test separately. This configuration
is persisted on disk.

Once that's done, use `neotest` the way you usually do: see
[their documentation](https://github.com/nvim-neotest/neotest#usage).
You don't need to call any `neotest-gtest` functions for ordinary usage.

## Configuration

`neotest-gtest` comes with the following defaults:

```lua
local utils = require("neotest-gtest.utils")
local lib = require("neotest.lib")

require("neotest-gtest").setup({
  -- fun(string) -> string: takes a file path as string and returns its project root
  -- directory
  -- neotest.lib.files.match_root_pattern() is a convenient factory for these functions:
  -- it returns a function that returns true if the directory contains any entries
  -- with matching names
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
  -- which debug adapter to use? dap.adapters.<this debug_adapter> must be defined.
  debug_adapter = "codelldb",
  -- fun(string) -> bool: takes a file path as string and returns true if it contains
  -- tests
  is_test_file = function(file)
    -- by default, returns true if the file stem starts with test_ or ends with _test
    -- the extension must be cpp/cppm/cc/cxx/c++
  end,
  -- How many old test results to keep on disk (stored in stdpath('data')/neotest-gtest/runs)
  history_size = 3,
  -- To prevent large projects from freezing your computer, there's some throttling
  -- for -- parsing test files. Decrease if your parsing is slow and you have a
  -- monster PC.
  parsing_throttle_ms = 10,
  -- set configure to a normal mode key which will run :ConfigureGtest (suggested:
  -- "C", nil by default)
  mappings = { configure = nil },
  summary_view = {
    -- How long should the header be in tests short summary?
    -- ________TestNamespace.TestName___________ <- this is the header
    header_length = 80,
    -- Your shell's colors, if the default ones don't work.
    shell_palette = {
      passed = "\27[32m",
      skipped = "\27[33m",
      failed = "\27[31m",
      stop = "\27[0m",
      bold = "\27[1m",
    },
  },
  -- What extra args should ALWAYS be sent to google test?
  -- if you want to send them for one given invocation only,
  -- send them to `neotest.run({extra_args = ...})`
  -- see :h neotest.RunArgs for details
  extra_args = {},
  -- see :h neotest.Config.discovery. Best to keep this as-is and set
  -- per-project settings in neotest instead.
  filter_dir = function(name, rel_path, root)
    -- see :h neotest.Config.discovery for defaults
  end,
})
```

## Contributing

All contributions are welcome. If you would like to contribute, but not sure how
to get started, please open an issue, and I'll do my best to help you.

Should you feel confident enough to write a PR on your own, please make sure to
include tests. The plugin is tested quite extensively, you can run `make` to run
the tests. Integration testsuite requires a functioning C++11 compiler, and will
download googletests as a submodule.

## License

MIT, see [LICENSE](https://github.com/alfaix/neotest-gtest/blob/main/LICENSE)

[neotest]: https://github.com/nvim-neotest/neotest
[google-test]: https://github.com/google/googletest
[nvim-dap]: https://github.com/mfussenegger/nvim-dap
[codelldb]: https://github.com/vadimcn/codelldb
[mason.nvim]: https://github.com/williamboman/mason.nvim
[nvim-dap-wiki]: https://github.com/mfussenegger/nvim-dap/wiki/C-C---Rust-(via--codelldb)
