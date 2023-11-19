local neotest = require("neotest")
local nio = require("nio")

local GlobalRegistry = require("neotest-gtest.executables.global_registry")
local utils = require("neotest-gtest.utils")
local M = {}

function M.configure_executable()
  nio.run(M._configure_executable_async)
end

function M._configure_executable_async()
  local marked = M._get_marked_positions()
  M._ensure_something_is_marked(marked)
  local root2positions = M._group_positions_by_root(marked)
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

function M._get_marked_positions()
  local positions = {}
  local prefix = "neotest-gtest:"
  for adapter, marked in pairs(neotest.summary.marked()) do
    if vim.startswith(adapter, prefix) then
      for _, position in pairs(marked) do
        positions[#positions + 1] = position
      end
    end
  end
  return positions
end

function M._ensure_something_is_marked(positions)
  if #positions == 0 then
    vim.notify(
      "Please mark the tests (or namespaces, files, dirs) first and then call :ConfigureGtest",
      vim.log.levels.INFO
    )
  end
end

function M._group_positions_by_root(positions)
  local root2positions = {}
  for _, position in pairs(positions) do
    local root = utils.position2root(position)
    if root2positions[root] == nil then
      root2positions[root] = {}
    end
    root2positions[root][#root2positions[root] + 1] = position
  end
  return root2positions
end

local function has_single_executable(exe2nodes)
  local k1, v1 = next(exe2nodes)
  return k1 ~= nil and next(exe2nodes, k1) == nil
end

function M._common_executable_for_positions(root2positions)
  local common_executable = nil
  for root, positions in pairs(root2positions) do
    local registry = GlobalRegistry:for_dir(root)
    for _, position in ipairs(positions) do
      local exe2nodes, missing = registry:find_executables(position)
      if missing or not has_single_executable(exe2nodes) then
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
    return nio.ui.input({
      prompt = "Enter path to executable:",
      completion = "file",
      default = default,
    })
  end

  local select_options = utils.tbl_copy(choices)
  select_options[#select_options + 1] = "Enter path..."
  local selected = nio.ui.select(select_options, { prompt = "Select executable for marked nodes:" })
  if selected == select_options[#select_options] then
    return nio.ui.input({
      prompt = "Enter path to executable:",
      completion = "file",
      default = default,
    })
  end
  return selected
end

return M
