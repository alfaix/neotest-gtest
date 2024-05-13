local neotest = require("neotest")
local nio = require("nio")

local GlobalRegistry = require("neotest-gtest.executables.global_registry")
local utils = require("neotest-gtest.utils")
local M = {}

function M._configure_executable_async()
  local root2positions = M._get_marked_root2positions()
  if not M._check_something_is_marked(root2positions) then
    return
  end
  local common_executable = M._common_executable_for_positions(root2positions)
  local marked_roots = vim.tbl_keys(root2positions)
  local executables = GlobalRegistry:list_executables(marked_roots)
  local executable = M._select_or_create_executable(executables, common_executable)

  if executable ~= nil then
    for root, positions in pairs(root2positions) do
      local registry = GlobalRegistry:for_dir(root)
      for _, position in ipairs(positions) do
        registry:update_executable(position, executable)
      end
    end
    neotest.summary.clear_marked()
  end
end

function M.configure_executable()
  return nio.run(M._configure_executable_async, function(ok, maybe_error)
    if not ok then
      assert(maybe_error, "success is false but error is not provided!")
      error(maybe_error)
    end
  end)
end

function M._get_marked_root2positions()
  local root2positions = {}
  local prefix = "neotest-gtest:"
  for adapter, marked in pairs(neotest.summary.marked()) do
    if vim.startswith(adapter, prefix) then
      local root = string.sub(adapter, #prefix + 1)
      if root2positions[root] == nil then
        root2positions[root] = {}
      end
      for _, position in pairs(marked) do
        root2positions[root][#root2positions[root] + 1] = position
      end
    end
  end
  return root2positions
end

function M._check_something_is_marked(root2positions)
  for _, positions in pairs(root2positions) do
    if not vim.tbl_isempty(positions) then
      return true
    end
  end

  vim.notify(
    "Please mark the relevant GTest files (or dirs) first and then call :ConfigureGtest",
    vim.log.levels.INFO
  )
  return false
end

local function has_single_key(exe2nodes)
  local k1, _ = next(exe2nodes)
  return k1 ~= nil and next(exe2nodes, k1) == nil
end

function M._common_executable_for_positions(root2positions)
  local common_executable = nil
  for root, positions in pairs(root2positions) do
    local registry = GlobalRegistry:for_dir(root)
    for _, position in ipairs(positions) do
      local exe2nodes, missing = registry:find_executables(position)
      if missing or not has_single_key(exe2nodes) then
        return nil
      end
      assert(exe2nodes, "must not be nil if missing is not nil")
      if common_executable == nil then
        common_executable, _ = next(exe2nodes)
      elseif exe2nodes[common_executable] == nil then
        return nil
      end
    end
  end
  return common_executable
end

function M._select_or_create_executable(choices, default)
  if #choices == 0 then
    return M._input_executable(default)
  end

  local select_options = utils.tbl_copy(choices)
  select_options[#select_options + 1] = "Enter path..."
  local idx = M._select_executable(select_options)
  if idx == nil then
    return nil
  end
  if idx == #select_options then
    return M._input_executable(default)
  end
  return select_options[idx]
end

function M._select_executable(options)
  nio.scheduler()
  local _, idx = nio.ui.select(options, { prompt = "Select executable for marked nodes:" })
  return idx
end

function M._input_executable(default)
  nio.scheduler()
  return nio.ui.input({
    prompt = "Enter path to executable:",
    completion = "file",
    default = default,
  })
end

return M
