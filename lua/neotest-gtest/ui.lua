local async = require("plenary.async")
local M = {}

---@class Field
---@field name string
---@field prompt string
---@field required boolean
---@field completion string

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
local function select_with_prompt(options, format, default, prompt,
    allow_string, completion)
    -- NB: these aren't the user's options, these have been processed with
    -- opts.format()
    local lines = {prompt}
    for i, opt in ipairs(options) do
        lines[i + 1] = string.format("%d. %s", i, format(opt))
    end
    if allow_string == nil then -- allow_string == false
        lines[#lines + 1] =
            "Enter a number from the list above (q or empty cancels): "
    else
        lines[#lines + 1] =
            "Enter a number from the list above  or enter a new value (q or empty cancels): "
    end
    local full_prompt = table.concat(lines, "\n")
    local result = input({
        prompt = full_prompt,
        default = default and tostring(default) or nil,
        completion = completion
    })
    if result == "q" or result == "" or result == nil then
        return nil, nil, nil
    end

    local int = tonumber(result)
    if int and int ~= math.floor(int) then int = nil end
    if int == nil and not allow_string then
        return nil, nil, "string entered when number was required"
    end
    if int ~= nil then
        if int < 1 or int > #options then
            return nil, nil, "index out of range"
        else
            return int, options[int], nil
        end
    end
end

function M.select(options, opts)
    opts = vim.tbl_extend("keep", opts or {}, {
        format = function(option) return option end,
        default = nil,
        allow_string = false,
        completion = nil
    })

    if not opts.prompt then
        opts.prompt = opts.allow_string and
                          "Select one of the options or enter a new one:" or
                          "Select one of the options:"
    end

    return select_with_prompt(options, opts.format, opts.default, opts.prompt,
                              opts.allow_string, opts.completion)
end

---Request input from the user. See `vim.ui.input` for documentation on options
---@param opts table {prompt = string, default = string, completion = string}
---@return string|nil Text as entered by the user
---@return string|nil Error if any (currently always nil)
function M.input(opts)
    opts = vim.tbl_extend("keep", opts or {},
                          {prompt = "Input: ", default = nil, completion = nil})
    local inpt = input({
        prompt = opts.prompt,
        default = opts.default,
        completion = opts.completion
    })

    if inpt == nil or inpt == "q" or inpt == "" then return nil, nil end
    return inpt, nil
end

function M.configure(fields, opts) end

return M
