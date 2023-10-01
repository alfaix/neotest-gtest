# neotest-gtest

A **work-in-progress** implementation of a [Google Test](https://github.com/google/googletest) adapter for [neotest](https://github.com/nvim-neotest/neotest).

It works, but is a little rough around the edges. See the roadmap to a full-featured plugin [here](https://github.com/alfaix/neotest-gtest/issues/1).
Please, submit any issues you find!

## Features
Provides support for all features of neotest:
* Structured test view
* Run file/test case/test suite
* Display errors in diagnostics
* Helpful short test summary in a popup
* Full test output (with colors!) in a popup

To be implemented (see [roadmap](https://github.com/alfaix/neotest-gtest/issues/1)):
* Running more than one file at a time
* Smart, configurable detection and recompilation of the test executable
* Support for parametrized tests
* Configurable behavior with working out-of-the-box defaults

## Installation
Use your favorite package manager. Don't forget to install [neotest](https://github.com/nvim-neotest/neotest) itself, which also has a couple dependencies.

For **debugging**, you alsoe need [nvim-dap](https://github.com/mfussenegger/nvim-dap), and a debug adapter ([codelldb](https://github.com/vadimcn/codelldb) recommended,
you can install it manually or with [mason.nvim](https://github.com/williamboman/mason.nvim)).
For setting it up, see [nvim-dap wiki](https://github.com/mfussenegger/nvim-dap/wiki/C-C---Rust-(via--codelldb))

### [lazy.nvim](https://github.com/folke/lazy.nvim)
```lua
-- best to add to dependencies of `neotest`
{ "alfaix/neotest-gtest" }
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)
```lua
use { "alfaix/neotest-gtest" }
```

### [vim-plug](https://github.com/junegunn/vim-plug)
```vim
Plug 'alfaix/neotest-gtest'
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
Then use `neotest` the way you usually do: see [their documentation](https://github.com/nvim-neotest/neotest#usage). 
You don't need to call any `neotest-gtest` functions for ordinary usage.

## Configuration
`neotest-gtest` comes with the following defaults:
```lua
local utils = require("neotest-gtest.utils")
local lib = require("neotest.lib")

require("neotest-gtest").setup({
    -- dap.adapters.<this debug_adapter> must be set for debugging to work
    -- see "installation" section above for installing and setting it up
    debug_adapter = "codelldb",

    -- Must be set to a function that takes a single string argument (full path to file)
    -- and returns its root. `neotest` provides a utility match_root_pattern,
    -- which will return the first parent directory containing one of these file names
    root = lib.files.match_root_pattern(
      "compile_commands.json",
      "compile_flags.txt",
      ".clangd",
      "init.lua",
      "init.vim",
      "build",
      ".git"
    ),

    -- takes full path to the file and returns true if it's a test file, false otherwise
    -- by default, returns true for all cpp files starting with "test_" or ending with
    -- "_test"
    is_test_file = utils.is_test_file
  }
)
```

## Contributing
All contributions (issues, PRs, wiki) are welcome. If you'd like to contribute a PR, but not sure what would be the best way to implement it, please open an issue and I'll help getting you started.

## License
MIT, see [LICENSE](https://github.com/alfaix/neotest-gtest/blob/main/LICENSE)
