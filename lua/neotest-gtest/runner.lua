local utils = require("neotest-gtest.utils")
local Path = require("plenary.path")
local scandir = require("plenary.scandir")
local ui = require("neotest-gtest.ui")

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

---Returns the runner for path `path`. If interactive is true and no runner is
---registered for the path, will prompt the user to select one.
---@param path string Test file path to return the runner for
---@param opts table Options, default: {interactive = false}
---@return neotest-gtest.Runner|nil the runer for the given path
---@return string|nil human-readable error (if any)
function M.runner_for(path, opts)
	opts = vim.tbl_extend("keep", opts or {}, { interactive = false })
	for _, runner in ipairs(M._runners) do
		if runner:owns(path) then
			return runner
		end
	end

	if not opts.interactive then
		return nil
	end

	local choice_idx, runner, error
	if #M._runners ~= 0 then
		local selected
		choice_idx, selected, error = ui.select(M._runners, {
			format = function(option)
				return option:executable()
			end,
			default = M._last_chosen,
			prompt = string.format("Choose the executable for %s (or enter a new path)", path),
			completion = "file",
			allow_string = true,
		})
		if error == nil then
			if choice_idx == nil then
				-- selected is the path to the test executable entered by the user
				choice_idx, runner, error = M.register_runner(selected, nil, { path })
			else
				runner = selected
			end
		end
	else
		local inpt
		inpt, error = ui.input({
			prompt = string.format("Enter the executable path for %s (q or empty cancels): ", path),
			completion = "file",
		})
		if error == nil and inpt then
			choice_idx, runner, error = M.register_runner(inpt, nil, { path })
		end
	end
	if error then
		return nil, error
	end
	if choice_idx ~= nil then
		M._last_chosen = choice_idx
	end
	return runner, nil
end

function M.select_runner(index, exe_path)
	if index ~= nil then
		return M._runners[index]
	end
	if exe_path ~= nil then
		exe_path = utils.normalize_path(exe_path)
		for _, runner in ipairs(M._runners) do
			if runner:executable() == exe_path then
				return runner
			end
		end
	end
	return nil
end

---Loads runners from an object previously saved with dump_runners().
---If `opts.clear`, will remove old runners before adding anything
---@param data neotest-gtest.RunnerInfo[]
---@param opts table Options, default: clear = true
---@returns boolean ok/not ok
---@returns string|nil error message if any
function M.load_runners(data, opts)
	local err
	opts = vim.tbl_extend("keep", opts or {}, { clear = true, on_error = "notify" })
	local runners = {}
	for _, runner_info in ipairs(data) do
		runners[#runners + 1], err =
			Runner:new(runner_info.executable_path, runner_info.compile_command, runner_info.paths)
		if opts.on_error == "propagate" then
			return false, err
		elseif opts.on_error == "notify" then
			vim.notify(
				string.format("Error loading executable at %s: %s", runner_info.executable_path or "<nil>", err),
				3
			)
		end
	end

	if opts.clear then
		M._runners = runners
	else
		M._runners = vim.tbl_flatten({ M._runners, runners })
	end
	return true
end

---Returns json-friendly list of registered runners. If `include_unused` is false,
---(the default), runners with no files associated with them will not be returned.
---@param opts table Options, default: {include_unused = false}
---@return neotest-gtest.RunnerInfo[]
function M.dump_runners(opts)
	opts = vim.tbl_extend("keep", opts or {}, { include_unused = false })
	local runners = {}
	for _, runner in ipairs(M._runners) do
		if opts.include_unused or runner:is_used() then
			runners[#runners + 1] = {
				executable_path = runner._run_command,
				compile_command = runner._compile_command,
				paths = runner._paths,
			}
		end
	end
	return runners
end

function M.register_runner(executable_path, compile_command, paths)
	executable_path = utils.normalize_path(executable_path)
	for i, runner in ipairs(M._runners) do
		if runner:executable() == executable_path then
			for _, path in ipairs(paths) do
				runner:add_path(path)
			end
			if compile_command then
				runner._compile_command = compile_command
			end
			return i, runner
		end
	end

	local runner, err = Runner:new(executable_path, compile_command, paths)
	if runner == nil then
		return nil, nil, err
	end
	local new_idx = #M._runners + 1
	M._runners[new_idx] = runner
	return new_idx, runner, nil
end

function Runner:new(executable_path, compile_command, paths)
	local runner = { _compile_command = compile_command, _paths = {} }
	setmetatable(runner, { __index = Runner })
	local ok, err = runner:set_executable(executable_path)
	if not ok then
		return nil, err
	end
	for _, path in ipairs(paths) do
		runner:add_path(path)
	end
	return runner, nil
end

function Runner:executable()
	return self._executable_path
end
function Runner:set_executable(executable_path)
	executable_path = utils.normalize_path(executable_path)
	local exists, err = utils.fexists(executable_path)
	if not exists then
		-- could also be permission denied, print the error
		return false, string.format("Cannot find an executable at path %s: %s", executable_path, err)
	end
	self._executable_path = executable_path
	return true, nil
end
function Runner:compile_command()
	return self._compile_command
end
function Runner:set_compile_command(command)
	self._compile_command = command
end

---Returns true if parent is equal to child or parent is a parent directory of child.
---Assumes both paths exist, are absolute and are normalized.
---@param parent string
---@param child string
---@return boolean
local function _is_parent(parent, child)
	local is_prefix = vim.startswith(child, parent)
	return is_prefix and (#parent == #child or child:sub(#parent + 1, #parent + 1) == Path.path.sep)
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

function Runner:configure(opts)
	opts = vim.tbl_extend(opts or {}, { fields = { "executable", "compile_command", "paths" } })
	local all_fields = {
		executable = {
			name = "executable",
			human_name = "the path to the test executable",
			default = self._executable_path,
			required = true,
			completion = "file",
		},
		compile_command = {
			name = "compile_command",
			human_name = "the compilation command",
			default = self._compile_command,
			required = false,
			completion = "file",
		},
		paths = {
			name = "paths",
			human_name = "test paths (files/directories)",
			default = table.concat(
				vim.tbl_map(function(path)
					return path:find("%s") and string.format("'%s'", path) or path
				end, self._paths),
				" "
			),
			required = true,
			completion = "file",
		},
	}
	local selected_fields = vim.tbl_map(function(field)
		return all_fields[field]
	end, opts.fields)
	local user_input = ui.configure(selected_fields)

	if vim.tbl_contains(opts.fields, "executable") then
		self:set_executable(user_input.executable)
	end

	if vim.tbl_contains(opts.fields, "paths") then
		local paths = utils.parse_words(user_input.paths)
		self._paths = {}
		for _, path in ipairs(paths) do
			self:add_path(path)
		end
	end

	if vim.tbl_contains(opts.fields, "compile_command") then
		self:set_compile_command(user_input.compile_command)
	end

	return true, nil
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

function Runner:root()
	local common_prefix = ""
	local adapter = require("neotest-gtest")
	local roots = vim.tbl_map(adapter.root, self._paths)
	while true do
		local slash = roots[1]:find(Path.path.sep, #common_prefix + 1, true)
		if slash == nil then
			return common_prefix
		end
		local new_prefix = roots[1]:sub(1, slash)
		for _, root in ipairs(roots) do
			if not vim.startswith(root, new_prefix) then
				return common_prefix
			end
		end
		common = new_prefix
	end
end

function Runner:recompile(opts)
	opts = vim.tbl_extend(opts or {}, { cwd = nil })
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

return M
