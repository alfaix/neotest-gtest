local utils = require("neotest-gtest.utils")
local Path = require("plenary.path")
local scandir = require("plenary.scandir")
local ui = require("neotest-gtest.ui")

local M = {}

--- Exposed UI:
--- M.ui.select_runner
--- M.ui.configure
--- M.ui.new
--- M.ui.drop
--
--- Exposed API
--- M.find_runners
--- M.drop_runner
--- M.add_runner
--- M.load_runners

---@class neotest-gtest.RunnerInfo
---@field private executable_path string
---@field private paths string[]

---@class neotest-gtest.Runner
---@field private _executable_path string
---@field private _paths string[]
local Runner = {}

M._runners = {}
M._runners_executable2idx = {}
M._last_chosen = nil

local function tbl_concat(lhs, rhs)
  for _, v in ipairs(rhs) do
    lhs[#lhs + 1] = v
  end
  return lhs
end

---@class neotest-gtest.RunnerDefaults
---@field private executable_path? string
---@field private paths? string[]

---Asks the user to fill information about a new runner and returns it.
---@param default_values neotest-gtest.RunnerDefaults
---@return neotest-gtest.Runner|nil Runner if creation succeeded
---@return string|nil error (if any)
local function new_runner(default_values)
  local fields = {
    {
      name = "executable",
      human_name = "the path to the test executable",
      default = default_values.executable_path,
      required = true,
      completion = "file",
    },
    {
      name = "paths",
      human_name = "test paths (files/directories)",
      default = table.concat(
        vim.tbl_map(function(path)
          return path:find("%s") and string.format("'%s'", path) or path
        end, default_values.paths or {}),
        " "
      ),
      required = true,
      completion = "file",
    },
  }
  local user_input, err = ui.configure(fields, nil)
  if err ~= nil then
    return nil, err
  end
  assert(user_input ~= nil, "user_input must not be nil")
  local paths, parse_err = utils.parse_words(user_input.paths)
  if parse_err ~= nil then
    return nil, err
  end
  return Runner:new(user_input.executable, paths)
end

local RunnerUI = {}

function RunnerUI.select_runner(list, opts)
  if list == nil then
    list = M._runners
  end
  local options
  if opts.suggest_create then
    options = { "Create a new runner" }
  else
    options = {}
  end

  local default_idx = options.default_idx
  for _, runner in ipairs(list) do
    options[#options + 1] = runner:executable()
    if
      options.with_last_used
      and M._last_chosen
      and M._runners_executable2idx[runner:executable()] == M._last_chosen
    then
      default_idx = #options
    end
  end

  local choice_idx, _, error = ui.select(options, {
    default = default_idx,
    prompt = opts.prompt or "Select a runner",
    allow_string = false,
  })
  if error ~= nil then
    return nil, error
  end

  if choice_idx == nil then
    return nil, "cancelled"
  end

  if opts.suggest_create then
    -- first option is "create a new runner"
    if choice_idx == 1 then
      return nil, nil
    end
    choice_idx = choice_idx - 1
  end

  local chosen = list[choice_idx]
  M._last_chosen = M._runners_executable2idx[chosen:executable()]
  return chosen, nil
end

-- Kinda tested
function RunnerUI.runner_for(path)
  if #M._runners == 0 then
    return nil, nil -- act as if the user requested to create a new one
  end
  local runners = M.find_runners({ owned_paths = { path } })
  if #runners == 1 then
    return runners[1], nil
  end

  -- select from all runners if there are no runners for the current path
  -- select from existing runners if there is more than one runner for the current path
  if #runners == 0 then
    runners = M._runners
  end
  return RunnerUI.select_runner(runners, {
    prompt = "Select a runner for " .. path,
    suggest_create = true,
    with_last_used = true,
  })
end

-- Kinda tested
function RunnerUI.configure()
  local selected, error = RunnerUI.select_runner(nil, {
    prompt = "Select a runner to configure",
    suggest_create = true,
    with_last_used = false,
  })
  if error ~= nil then
    return nil, error
  end
  if selected == nil then
    return RunnerUI.new()
  end

  local defaults = {
    executable_path = selected:executable(),
    paths = selected._paths,
  }

  local new
  new, error = new_runner(defaults)
  if error ~= nil then
    return error
  end
  assert(new ~= nil, "new runner must not be nil")

  if new._executable_path ~= selected._executable_path then
    M._runners_executable2idx[new._executable_path] =
      M._runners_executable2idx[selected._executable_path]
    M._runners_executable2idx[selected._executable_path] = nil
    selected._executable_path = new._executable_path
  end
  selected._paths = new._paths
end

-- Kinda tested
function RunnerUI.new(defaults)
  defaults = defaults or {}
  local new, error = new_runner(defaults)
  if error ~= nil then
    return nil, error
  end
  assert(new ~= nil, "new runner must not be nil with no error")

  -- If the user entered an existing executable path, just update all the paths
  if M._runners_executable2idx[new._executable_path] ~= nil then
    vim.notify(
      string.format(
        "Runner at path %s already exists, updating paths instead",
        new._executable_path
      ),
      2
    )
    local existing = M._runners[M._runners_executable2idx[new._executable_path]]
    for _, path in ipairs(new._paths) do
      existing:add_path(path)
    end
    return existing
  end

  return M.add_runner(new)
end

-- Kinda tested
function RunnerUI.drop()
  if #M._runners == 0 then
    return nil, "No runners to drop"
  end
  local runner, error = RunnerUI.select_runner(nil, {
    prompt = "Select a runner to delete",
    suggest_create = false,
    with_last_used = false,
  })
  if error ~= nil then
    return nil, error
  end
  assert(runner ~= nil, "runner cannot be nil with no error (suggest_create = false)")
  return M.drop_runner(runner)
end

M.ui = RunnerUI

---@class neotest-gtest.RunnerSearchCriteria
---@field owned_paths string[]?
---@field executable_path string?

---Finds all runners satisfying the criteria.
---@param criteria neotest-gtest.RunnerSearchCriteria Search criteria. If
---       executable_path is not nil, at most one runner will be returned. If
---       both fields are nil, all runners will be returned.
---@return neotest-gtest.Runner[]
function M.find_runners(criteria) -- kinda tested
  local executable_path = criteria.executable_path
  if executable_path ~= nil then
    if M._runners_executable2idx[executable_path] ~= nil then
      return { M._runners[M._runners_executable2idx[executable_path]] }
    end
    return {}
  end

  local owned_paths = criteria.owned_paths
  if owned_paths == nil or #owned_paths == 0 then
    -- shallow copy: we don't want the user to modify the original table
    return vim.tbl_map(function(x)
      return x
    end, M._runners)
  end

  local result = {}
  for _, runner in ipairs(M._runners) do
    local owns_all = true
    for _, owned_path in ipairs(owned_paths) do
      if not runner:owns(owned_path) then
        owns_all = false
        break
      end
    end
    if owns_all then
      result[#result + 1] = runner
    end
  end
  return result
end

---Removes the given runner from the list of runners.
---@param runner_or_executable string|neotest-gtest.Runner executable path of
---       the runner to remove or the runner itself.
---@return neotest-gtest.Runner|nil the removed runner
---@return string|nil error if the runner is not found
function M.drop_runner(runner_or_executable) -- kinda tested
  local runner, index
  if type(runner_or_executable) == "string" then
    local path = utils.normalize_path(runner_or_executable)
    index = M._runners_executable2idx[path]
    if index == nil then
      return nil, "Runner not found"
    end
    runner = M._runners[index]
    assert(runner ~= nil, "runners_executable2idx is out of sync")
  else
    runner = runner_or_executable
    index = M._runners_executable2idx[runner:executable()]
    if index == nil then
      return nil, "Runner not found"
    end
  end

  table.remove(M._runners, index)
  M._runners_executable2idx[runner:executable()] = nil
  return runner, nil
end

---Adds the given runner to the internal registry.
---@param runner neotest-gtest.Runner Runner to add
---@return neotest-gtest.Runner The added runner, if succeeded
---@return string|nil Human-readable error (if runner with that executable already exists)
function M.add_runner(runner) -- kinda tested
  if M._runners_executable2idx[runner:executable()] ~= nil then
    return nil, "Runner already exists"
  end
  local new_idx = #M._runners + 1
  M._runners[new_idx] = runner
  M._runners_executable2idx[runner:executable()] = new_idx
  return runner, nil
end

---Loads runners from a list of runners serialized by Runner:to_json()
---If `opts.clear`, will remove old runners before adding anything
---@param data neotest-gtest.RunnerInfo[]
---@param opts table Options, default: clear = true
---@returns boolean ok/not ok
---@returns string|nil error message if any
function M.load_runners(data, opts) -- kinda tested
  local err
  opts = vim.tbl_extend("keep", opts or {}, { clear = true, on_error = "notify" })
  local runners = {}
  for _, runner_info in ipairs(data) do
    runners[#runners + 1], err = Runner:from_json(runner_info)
    if err then
      if opts.on_error == "propagate" then
        return false, err
      elseif opts.on_error == "notify" then
        vim.notify(
          string.format(
            "Error loading runner at %s: %s",
            runner_info.executable_path or "<nil>",
            err
          ),
          3
        )
      end
    end
  end

  if opts.clear then
    M._runners = runners
    for i, runner in ipairs(runners) do
      M._runners_executable2idx[runner:executable()] = i
    end
  else
    M._runners = tbl_concat(M._runners, runners)
    for i, runner in ipairs(runners) do
      M._runners_executable2idx[runner:executable()] = i + #M._runners
    end
  end
  return true
end

function Runner:new(executable_path, paths)
  local runner = { _paths = {} }
  setmetatable(runner, { __index = Runner })
  local ok, err = runner:_set_executable(executable_path)
  if not ok then
    return nil, err
  end
  for _, path in ipairs(paths) do
    runner:add_path(path)
  end
  return runner, nil
end

---Builds a runner from a JSON table created by to_json()
---@param data table JSON created by to_json()
---@return table, string|nil Runner object, error message (if any)
function Runner:from_json(data)
  return self:new(data.executable_path, data.paths)
end

function Runner:to_json()
  return {
    executable_path = self._executable_path,
    paths = self._paths,
  }
end

function Runner:executable()
  return self._executable_path
end

function Runner:_set_executable(executable_path)
  executable_path = utils.normalize_path(executable_path)
  local exists, err = utils.fexists(executable_path)
  if not exists then
    -- could also be permission denied, print the error
    return false, string.format("Cannot find an executable at path %s: %s", executable_path, err)
  end
  self._executable_path = executable_path
  return true, nil
end

---Returns true if parent is equal to child or parent is a parent directory of child.
---Assumes both paths exist, are absolute and are normalized.
---@param parent string
---@param child string
---@return boolean
local function _is_parent(parent, child)
  local is_prefix = vim.startswith(child, parent)
  return is_prefix
    and (
      #parent == #child -- same path
      or parent:sub(#parent, #parent) == Path.path.sep -- parent ends with /
      -- parent is a directory, next symbol in child is /
      or child:sub(#parent + 1, #parent + 1) == Path.path.sep
    )
end

function Runner:owns(path)
  path = utils.normalize_path(path)
  for _, owned_path in ipairs(self._paths) do
    if _is_parent(owned_path, path) then
      return true
    end
  end
  return false
end

---Adds path to the owned paths list. It is guaranteed Runner:owns(path) will
---return true after this, though the path may not be added if its parents are
---already owned.
---@param path string
function Runner:add_path(path)
  path = utils.normalize_path(path)
  for _, owned_path in ipairs(self._paths) do
    -- already owned: do nothing
    if _is_parent(owned_path, path) then
      return
    end
  end
  local children = {}
  for i, owned_path in ipairs(self._paths) do
    if _is_parent(path, owned_path) then
      children[i] = true
    end
  end
  if vim.tbl_isempty(children) then
    self._paths[#self._paths + 1] = path
  else
    local new_paths = {}
    for i, owned_path in ipairs(self._paths) do
      if not children[i] then
        new_paths[#new_paths + 1] = owned_path
      end
    end
    new_paths[#new_paths + 1] = path
    self._paths = new_paths
  end
end

function Runner:is_used()
  for _, owned_path in ipairs(self._paths) do
    local pathobj = Path:new(owned_path)
    if pathobj:exists() then
      if pathobj:is_dir() then
        local test_files = scandir.scan_dir(pathobj, {
          add_dirs = false,
          respect_gitignore = false,
          search_pattern = utils.is_test_file,
          silent = true,
        })
        if #test_files ~= 0 then
          return true
        end
      elseif utils.is_test_file(pathobj.filename) then
        return true
      end
    end
  end
  return false
end

M.Runner = Runner

return M
