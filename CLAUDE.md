# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

neotest-gtest is a Neovim plugin that adapts Google Test (C++ testing framework) for use with neotest. It provides test discovery via tree-sitter parsing, test execution, result display, and debugging integration.

## Build and Test Commands

```bash
# Run all tests (unit + integration)
make test

# Run only unit tests (fast, no compilation)
make unit-test

# Run only integration tests (requires C++ compiler)
make integration-test

# Build C++ test binaries without running tests
make build-tests

# Clean C++ test builds
make clean-tests

# Test against a specific GTest version
GTEST_TAG=v1.14.0 make integration-test

# Test all supported GTest versions
make integration-test-all
```

## Code Style

Uses StyLua for Lua formatting (config in `stylua.toml`):
- 100 character line width, 2-space indentation, double quotes

```bash
stylua lua/ tests/           # Format code
stylua --check lua/ tests/   # Check without modifying
```

## Architecture

### Core Components (`lua/neotest-gtest/`)

- **init.lua** - Entry point, registers adapter with neotest, exposes public API
- **neotest_adapter.lua** - Implements neotest adapter interface (`build_spec`, `results`, `discover_positions`)
- **parse.lua** - Tree-sitter queries for discovering TEST/TEST_F/TEST_P macros in C++ files
- **report.lua** - Parses Google Test JSON output into neotest result format
- **config.lua** - Configuration with defaults and validation
- **storage.lua** - Persistent storage for executable mappings
- **utils.lua** - Root detection, path normalization, error scheduling

### Executable Management (`lua/neotest-gtest/executables/`)

Maps test files to their compiled executables:
- **registry.lua** - Per-project executable registry
- **global_registry.lua** - Cross-project global registry
- **ui.lua** - User interface for `:ConfigureGtest` command

### Test Structure

- **tests/unit/** - Lua unit tests using Plenary (`*_spec.lua`)
- **tests/integration/** - Full integration tests with real C++ compilation
- **tests/integration/cpp/** - Sample C++ test projects
- **tests/utils/** - Test helper utilities and mocks

## Key Patterns

**Tree-sitter Test Discovery**: The parser in `parse.lua` uses a precise tree-sitter query to identify Google Test macros. It matches function definitions without return types that have exactly 2 unnamed parameters and names matching TEST/TEST_F/TEST_P.

**Two-Level Registry**: Executable mappings are stored in `stdpath('data')/neotest-gtest/` with global defaults and per-project overrides.

**Async Operations**: Uses `nvim-nio` for non-blocking I/O throughout.

## Testing Notes

- Unit tests run with Plenary's test framework (`describe`/`it` blocks)
- Tests require: neovim 0.9.1+, nvim-treesitter with C++ parser, plenary.nvim, neotest, nvim-nio
- Integration tests compile real C++ code and require a C++11 compiler and CMake
- CI tests against Neovim versions: 0.9.1, 0.10.0, nightly
- CI tests against GTest versions: 1.10.0, 1.11.0, 1.12.1, 1.13.0, 1.14.0, main

## Known Limitations

- TEST_P (parameterized tests) discovery not yet supported
- No automatic build tool integration (manual compilation required)
