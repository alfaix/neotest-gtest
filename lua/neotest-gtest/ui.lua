local async = require("plenary.async")
local lib = require("neotest.lib")

local M = {}

local input = async.wrap(vim.ui.input, 2)

---Prompts the user to select one of `options` or (optionally) enter a new value
---@param options any[] The list of options to choose from.
---@param default string? The default value to be entered
---@param prompt string? The prompt to display above the options
---@param completion string? The completion, a string as in
--        `:h command-completion` or nil
---@return number? Selected option. Nil if was cancelled or a string was entered.
---@return any The selected option or the entered string, if allowed
---@return string Error message, if any
local function select_with_prompt(options, format, default, prompt, allow_string, completion)
	-- NB: these aren't the user's options, these have been processed with
	-- opts.format()
	local lines = { prompt }
	for i, opt in ipairs(options) do
		lines[i + 1] = string.format("%d. %s", i, format(opt))
	end
	if allow_string == nil then -- allow_string == false
		lines[#lines + 1] = "Enter a number from the list above (q or empty cancels): "
	else
		lines[#lines + 1] = "Enter a number from the list above  or enter a new value (q or empty cancels): "
	end
	local full_prompt = table.concat(lines, "\n")
	local result = input({
		prompt = full_prompt,
		default = default and tostring(default) or nil,
		completion = completion,
	})
	if result == "q" or result == "" or result == nil then
		return nil, nil, nil
	end

	local int = tonumber(result)
	if int == nil or int ~= math.floor(int) then
		if allow_string then
			return nil, result, nil
		end
		return nil, nil, "string entered when number was required"
	end

	if int < 1 or int > #options then
		return nil, nil, "index out of range"
	else
		return int, options[int], nil
	end
end

function M.select(options, opts)
	opts = vim.tbl_extend("keep", opts or {}, {
		format = function(option)
			return option
		end,
		default = nil,
		allow_string = false,
		completion = nil,
	})

	if not opts.prompt then
		opts.prompt = opts.allow_string and "Select one of the options or enter a new one:"
			or "Select one of the options:"
	end

	return select_with_prompt(options, opts.format, opts.default, opts.prompt, opts.allow_string, opts.completion)
end

---Request input from the user. See `vim.ui.input` for documentation on options
---@param opts table {prompt = string, default = string, completion = string}
---@return string|nil Text as entered by the user
---@return string|nil Error if any (currently always nil)
function M.input(opts)
	opts = vim.tbl_extend("keep", opts or {}, { prompt = "Input: ", default = nil, completion = nil })
	local inpt = input({
		prompt = opts.prompt,
		default = opts.default,
		completion = opts.completion,
	})

	if inpt == nil or inpt == "q" or inpt == "" then
		return nil, nil
	end
	return inpt, nil
end

---@class Field
---@field name string
---@field human_name? string
---@field default? string
---@field required boolean
---@field completion? string

---Requests user input for `fields`, one input at a time.
---@param fields Field[] fields to request from the user
---@param _ table Options, currently unused
---@return table|nil Table field.name -> user input
---@return string|nil Error if any
function M.configure(fields, _)
	local values = {}
	for _, field in ipairs(fields) do
		local name = field.human_name or field.name
		local prompt
		if field.required then
			prompt = string.format("Enter %s (required): ", name)
		else
			prompt = string.format("Enter %s (empty to leave unfilled): ", name)
		end
		local inpt, err = M.input({
			prompt = prompt,
			default = field.default or "",
			completion = field.completion,
		})
		if err then
			return nil, err
		end
		if inpt == "" then
			inpt = nil
		end
		if field.required and not inpt then
			return nil, string.format("required filled %s left empty", name)
		end
		values[field.name] = inpt
	end
	return values, nil
end

-- This function is largely copypasted from neotest.consumers.output
-- Their copyright and license are available at https://github.com/nvim-neotest/neotest
function M.show_output(output, opts)
	local buf = async.api.nvim_create_buf(false, true)
	local chan = async.api.nvim_open_term(buf, {})
	-- See https://github.com/neovim/neovim/issues/14557
	local dos_newlines = string.find(output, "\r\n") ~= nil
	async.api.nvim_chan_send(chan, dos_newlines and output or output:gsub("\n", "\r\n"))
	async.util.sleep(10) -- Wait for chan to send
	local lines = async.api.nvim_buf_get_lines(buf, 0, -1, false)
	local width, height = 80, #lines
	for i, line in ipairs(lines) do
		if i > 500 then
			break -- Don't want to parse very long output
		end
		local line_length = vim.str_utfindex(line)
		if line_length > width then
			width = line_length
		end
	end

	local on_close = function()
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
		pcall(vim.fn.chanclose, chan)
	end
	local float = lib.ui.float.open({
		width = width,
		height = height,
		buffer = buf,
		enter = opts.enter,
	})
	float:listen("close", on_close)

	async.api.nvim_buf_set_keymap(buf, "n", "q", "", {
		noremap = true,
		silent = true,
		callback = function()
			pcall(vim.api.nvim_win_close, win, true)
		end,
	})
end

return M
