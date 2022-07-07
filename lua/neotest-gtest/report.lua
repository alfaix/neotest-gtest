local Report = {}

local header_size = 80 -- TODO allow configuring these
local palette = {
    skipped = "\27[33m",
    passed = "\27[32m",
    failed = "\27[31m",
    bold_header = true,
    bold_error = true
}
local COLOR_BOLD = "\27[1m"
local COLOR_STOP = "\27[0m"

local function range_contains(range, line)
    -- range is linstart, colstart, lineend, colend
    -- we ignore cols because Google Test doesn't report them. If someone writes
    -- multiple tests on the same line that's on them.
    return range[1] <= line and range[3] >= line
end

function Report:new(gtest_data, tree)
    local obj = {_gtest_data = gtest_data}
    setmetatable(obj, {__index = self})
    obj._node = tree:get_key(obj:position_id())
    return obj
end

function Report:name() return self:data().name end
function Report:namespace() return self:data().classname end

function Report:position_id()
    if self._position_id == nil then
        local test = self:data()
        self._position_id = table.concat({test.file, test.classname, test.name},
                                         "::")
    end
    return self._position_id
end

function Report:data() return self._gtest_data end

function Report:status()
    if self._status == nil then
        local test = self:data()
        if test.result == "SKIPPED" or test.status == "NOTRUN" then
            self._status = "skipped"
        else
            assert(test.result == "COMPLETED", "unknown result")
            self._status = #(test.failures or {}) == 0 and "passed" or "failed"
        end
    end
    return self._status
end

---@class GTestError
---@field failure string
---@field type string

---@param error GTestError
---@return neotest.Error
function Report:_error_info(error)
    local message = error.failure
    local test_data = self._node:data()
    if message == nil then return {message = "unknown error"} end
    -- split first line: it represents location, the rest is an arbitrary message
    local linebreak = message:find("\n")
    local location = message:sub(1, linebreak - 1)
    message = message:sub(linebreak + 1)
    local filename, linenum = location:match("(.*)%:(%d+)$")
    -- 3 cases:
    -- First line is "unknown file": exception thrown somewhere
    -- First line is "/path/to/file:linenum", the failure is insde the test
    -- First line is "/path/to/file:linenum", the failure is outside the test
    local header
    if linenum ~= nil then
        linenum = tonumber(linenum)
        assert(filename ~= nil, "error format not understood")
        if filename == test_data.path then
            header = string.format("Assertion failure at line %d:", linenum)
            -- Do not show diagnostics outside of test: multiple tests can show
            -- the same line, which will likely lead to confusion
            -- TODO: Investigate alternatives, such as showing all errors with
            -- test names
            if not range_contains(test_data.range, linenum) then
                linenum = nil
            end
        else
            header = string.format("Assertion failure in %s at line %d:",
                                   filename, linenum)
            linenum = nil
        end
    else
        assert(filename == nil, "error format not understood")
        -- file is unknown: do not repeat ourselves. GTest will say everything
        header = ""
    end
    return {
        message = header and (header .. "\n" .. message) or message,
        pretty_message = table.concat({
            palette.failed, palette.bold_header and COLOR_BOLD or "", header,
            header and COLOR_STOP or "", "\n", message, header or ""
        }),
        palette[error],
        -- gogle test ines are 1-indexed, neovim expects 0-indexed
        line = linenum and linenum - 1
    }
end

function Report:make_errors_list()
    if self._errors == nil then
        self._errors = vim.tbl_map(function(e) return self:_error_info(e) end,
                                   self:data().failures or {})
    end
    return self._errors
end

---@param full_output string Path to a text file with full test output
---@return neotest.Result
function Report:to_neotest_report(full_output)
    return {
        status = self:status(),
        output = full_output,
        short = self:make_summary(),
        errors = self:make_errors_list()
    }
end

---@return string Human-friendly summary of the text to be displayed by neotest
function Report:make_summary()
    if self._summary == nil then
        local lines = {}
        local status = self:status()
        local test = self:data()
        local errors = self:make_errors_list()
        if header_size > 0 then
            local full_name = string.format("%s.%s", test.classname, test.name)
            if #full_name >= header_size then
                lines[#lines + 1] = full_name
            else
                local padding = (header_size - #full_name) / 2
                local pad_left = string.rep("_", math.floor(padding))
                local pad_right = string.rep("_", math.ceil(padding))
                local color = palette[status] ..
                                  (palette.bold_header and COLOR_BOLD or "")
                local header = string.format("%s%s%s%s%s", color, pad_left,
                                             full_name, pad_right, COLOR_STOP)
                lines[#lines + 1] = header
            end
        end

        if status ~= "skipped" then
            local error_string
            if #errors ~= 0 then
                error_string = string.format("Errors: %d", #errors)
            else
                error_string = "Passed"
            end
            lines[#lines + 1] = string.format("%s, Time: %s, Timestamp: %s",
                                              error_string, test.time,
                                              test.timestamp)
        end

        for _, err in ipairs(errors) do
            lines[#lines + 1] = err.pretty_message
        end
        self._summary = table.concat(lines, "\n")
    end
    return self._summary
end

return Report
