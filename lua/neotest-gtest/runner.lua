local async = require("plenary.async")
local utils = require("neotest-gtest.utils")
local Path = require("plenary.path")
local scandir = require("plenary.scandir")

local M = {}

---@class neotest-gtest.RunnerInfo
---@field private executable_path string
---@field private compile_command? string
---@field private paths string[]

---@class neotest-gtest.Runner
---@field private _executable_path string
---@field private _compile_command? string
---@field private _paths string[]
local Runner = {}

M._runners = {}
M._last_chosen = nil

local input = async.wrap(vim.ui.input, 2)

local function choose_runner(path)
    local options = {}
    options[1] = string.format(
        "Choose the executable for %s (or enter a new path)\n", path)
    for i, runner in ipairs(M._runners) do
        options[#options + 1] =
            string.format("%d. %s\n", i, runner:executable())
    end
    options[#options + 1] =
        "Enter the number of the executable (q or empty cancels): "
    local prompt = table.concat(options, "")
    local inpt = input({
        prompt = prompt,
        default = M.last_chosen and tostring(M.last_chosen),
        completion = "file",
        cancelreturn = ""
    })

    if inpt == "q" or inpt == "" then return nil end
    local chosen = tonumber(inpt)
    if chosen == nil then
        return M.register_runner(inpt, nil, {path})
    elseif chosen > #M._runners or chosen < 1 then
        error(inpt .. " is out of range")
    else
        local runner = M._runners[chosen]
        runner:add_path(path)
        return chosen, runner
    end

end

---Returns the runner for path `path`. If interactive is true and no runner is
---registered for the path, will prompt the user to select one.
---@param path string Test file path to return the runner for
---@param opts table Options, default: {interactive = false}
---@return neotest-gtest.Runner
function M.runner_for(path, opts)
    opts = vim.tbl_extend("keep", opts or {}, {interactive = false})
    for _, runner in ipairs(M._runners) do
        if runner:owns(path) then return runner end
    end

    if not opts.interactive then return nil end

    local choice_idx, runner
    if #M._runners ~= 0 then
        choice_idx, runner = choose_runner(path)
    else
        local prompt = string.format(
            "Enter the executable path for %s (q or empty cancels): ", path)
        local inpt = input({
            prompt = prompt,
            default = "",
            completion = "file",
            cancelreturn = ""
        })
        if inpt ~= nil and inpt ~= "q" and inpt ~= "" then
            choice_idx, runner = M.register_runner(inpt, nil, {path})
        end
    end
    if choice_idx ~= nil then M._last_chosen = choice_idx end
    return runner
end

---Loads runners from an object previously saved with dump_runners().
---If `opts.clear`, will remove old runners before adding anything
---@param data neotest-gtest.RunnerInfo[]
---@param opts table Options, default: clear = true
function M.load_runners(data, opts)
    opts = vim.tbl_extend("keep", opts or {}, {clear = true})
    if opts.clear then M._runners = {} end
    for _, runner_info in ipairs(data) do
        M._runners[#M._runners + 1] = Runner:new(runner_info.executable_path,
                                                 runner_info.compile_command,
                                                 runner_info.paths)
    end
end

---Returns json-friendly list of registered runners. If `include_unused` is false,
---(the default), runners with no files associated with them will not be returned.
---@param opts table Options, default: {include_unused = false}
---@return neotest-gtest.RunnerInfo[]
function M.dump_runners(opts)
    opts = vim.tbl_extend("keep", opts or {}, {include_unused = false})
    local runners = {}
    for _, runner in ipairs(M._runners) do
        if opts.include_unused or runner:is_used() then
            runners[#runners + 1] = {
                executable_path = runner._run_command,
                compile_command = runner._compile_command,
                paths = runner._paths
            }
        end
    end
    return runners
end

function M.register_runner(executable_path, compile_command, paths)
    executable_path = utils.normalize_path(executable_path)
    for i, runner in ipairs(M._runners) do
        if runner:executable() == executable_path then
            for _, path in ipairs(paths) do runner:add_path(path) end
            if compile_command then
                runner._compile_command = compile_command
            end
            return i, runner
        end
    end

    local runner = Runner:new(executable_path, compile_command, paths)
    local new_idx = #M._runners + 1
    M._runners[new_idx] = runner
    return new_idx, runner
end

function Runner:new(executable_path, compile_command, paths)
    -- normalized by register_runner
    -- executable_path = normalize_path(executable_path)
    local exists, err = utils.fexists(executable_path)
    if not exists then
        -- could also be permission denied, print the error
        error(string.format("Cannot find an executable at path %s: %s",
                            executable_path, err))
    end
    local runner = {
        _executable_path = executable_path,
        _compile_command = compile_command,
        _paths = vim.tbl_map(utils.normalize_path, paths)
    }
    setmetatable(runner, {__index = Runner})
    return runner
end
function Runner:executable() return self._executable_path end
function Runner:compile_command() return self._compile_command end

---Returns true if parent is equal to child or parent is a parent directory of child.
---Assumes both paths exist, are absolute and are normalized.
---@param parent string
---@param child string
---@return boolean
local function _is_parent(parent, child)
    local is_prefix = vim.startswith(child, parent)
    return is_prefix and
               (#parent == #child or #child[#parent + 1] == Path.path.sep)
end

function Runner:owns(path)
    path = utils.normalize_path(path)
    for _, owned_path in ipairs(self._paths) do
        if _is_parent(owned_path, path) then return true end
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
        if _is_parent(owned_path, path) then return end
    end
    local children = {}
    for i, owned_path in ipairs(self._paths) do
        if _is_parent(path, owned_path) then children[i] = true end
    end
    if #children == 0 then
        self._paths[#self._paths + 1] = path
    else
        local new_paths = {}
        for i, owned_path in ipairs(self._paths) do
            if not children[i] then
                new_paths[#new_paths + 1] = owned_path
            end
        end
        new_paths[#new_paths + 1] = path
    end
end

-- TODO
function Runner:recompile(opts) end

function Runner:is_used()
    for _, owned_path in ipairs(self._paths) do
        local pathobj = Path:new(owned_path)
        if pathobj:exists() then
            if pathobj:is_dir() then
                local test_files = scandir.scan_dir(pathobj, {
                    add_dirs = false,
                    respect_gitignore = false,
                    search_pattern = utils.is_test_file,
                    silent = true
                })
                if #test_files ~= 0 then return true end
            elseif utils.is_test_file(pathobj.filename) then
                return true
            end
        end
    end
    return false
end

return M
