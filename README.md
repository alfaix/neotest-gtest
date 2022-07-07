# neotest-gtest
A **work-in-progress** implementation of a [Google Test](https://github.com/google/googletest) adapter for [neotest](https://github.com/nvim-neotest/neotest).

It works, but is a little rough around the edges. See the roadmap to a full-featured plugin [here](https://github.com/alfaix/neotest-gtest/issues/1).
Please, submit any issues you find!

## Features
Provides support for all features of neotest:
* Structured test view
* Run file/directory/test case/test suite
* Display errors in diagnostics
* Helpful short test summary in a popup
* Full test output (with colors!) in a popup

To be implemented (see [roadmap](https://github.com/alfaix/neotest-gtest/issues/1)):
* Smart, configurable detection and recompilation of the test executable
* Support for parametrized tests
* Configurable behavior with working out-of-the-box defaults

## Installation
Use your favorite package manager. Don't forget to install [neotest](https://github.com/nvim-neotest/neotest) itself, which also has a couple dependencies.

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
    require("neotest-gtest")
  }
})
```
Then use neotest the way you usually do: see their [documentation](https://github.com/nvim-neotest/neotest#usage). 
You don't need to call any `neotest-gtest` functions for ordinary usage.

## Configuration
Things aren't configurable at the moment, but they sure will be! :') You can track the progress by subscribing to the [roadmap](https://github.com/alfaix/neotest-gtest/issues/1) issue.

## License
MIT, see [LICENSE](https://github.com/alfaix/neotest-gtest/blob/main/LICENSE)
