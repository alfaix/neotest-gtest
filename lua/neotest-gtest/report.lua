local utils = require("neotest-gtest.utils")
local lib = require("neotest.lib")
local config = require("neotest-gtest.config")

---@class neotest-gtest.Report
---@field _result_json table
---@field _gtest_json table
local Report = {}

local function colors()
  return config.summary_view.shell_palette
end

---@return neotest-gtest.Report
function Report:new(gtest_data, tree)
  local obj = { _gtest_json = gtest_data }
  setmetatable(obj, { __index = self })
  obj._node = tree:get_key(obj:position_id()):data()
  return obj
end

function Report:position_id()
  if self._position_id == nil then
    local test = self._gtest_json
    local abs_file = utils.normalize_path(test.file)
    self._position_id = table.concat({ abs_file, test.classname, test.name }, "::")
  end
  return self._position_id
end

---@param full_output string Path to a text file with full test output
---@return neotest.Result
function Report:to_neotest_report(full_output)
  return {
    status = self:_build_status(),
    output = full_output,
    short = self:_build_summary(),
    errors = self:_build_errors_list(),
  }
end

---@return "passed"|"failed"|"skipped"
function Report:_build_status()
  if self._status == nil then
    local test = self._gtest_json
    if test.result == "SKIPPED" or test.status == "NOTRUN" then
      self._status = "skipped"
    else
      assert(test.result == "COMPLETED", "unknown result")
      self._status = #(test.failures or {}) == 0 and "passed" or "failed"
    end
  end
  return self._status
end

---@return string summary Human-friendly summary for the test
function Report:_build_summary()
  if self._summary == nil then
    local lines = {}
    lines[1] = self:_make_summary_header()
    lines[2] = self:_make_summary_subheader()

    local errors = self:_build_errors_list()
    for _, err in ipairs(errors) do
      lines[#lines + 1] = err.pretty_message
    end
    self._summary = table.concat(lines, "\n")
  end
  return self._summary
end

function Report:_make_summary_header()
  local t = self._gtest_json
  local full_name = string.format("%s.%s", t.classname, t.name)
  local status = self:_build_status()
  local text = self:_pad_with_underscores(full_name)
  local color = colors()[status] .. colors().bold
  return string.format("%s%s%s", color, text, colors().stop)
end

function Report:_pad_with_underscores(text)
  local len = config.summary_view.header_length
  if #text >= len then
    return text
  end
  local padding_length = (len - #text) / 2
  local pad_left = string.rep("_", math.floor(padding_length))
  local pad_right = string.rep("_", math.ceil(padding_length))
  return string.format("%s%s%s", pad_left, text, pad_right)
end

function Report:_make_summary_subheader()
  local t = self._gtest_json
  local status = self:_build_status()
  local num_errors = #(self:_build_errors_list())
  if status == "skipped" then
    return "Test skipped, Timestamp: " .. t.timestamp
  elseif status == "passed" then
    return string.format("Passed, Time: %s, Timestamp: %s", t.time, t.timestamp)
  else
    return string.format("Errors: %d, Time: %s, Timestamp: %s", num_errors, t.time, t.timestamp)
  end
end

---@class neotest-gtest.GTestError
---@field failure? string
---@field type? string

---@class neotest-gtest.ParsedGtestError
---@field filename? string
---@field linenum? number
---@field header? string
---@field body string

---@param gtest_error neotest-gtest.GTestError
---@return neotest.Error
function Report:_error_info(gtest_error)
  local parsed_error = self:_parse_gtest_error(gtest_error)

  local neotest_error = {
    message = parsed_error.body,
    pretty_message = self:_format_pretty_error_message(parsed_error),
    colors()[gtest_error],
  }

  if parsed_error.linenum ~= nil and parsed_error.filename == self._node.path then
    -- gogle test ines are 1-indexed, neovim expects 0-indexed
    -- also neotest only shows errors in the same file as the test
    neotest_error.line = parsed_error.linenum - 1
  end

  return neotest_error
end

---@param gtest_error neotest-gtest.GTestError
---@return neotest-gtest.ParsedGtestError
function Report:_parse_gtest_error(gtest_error)
  local message = gtest_error.failure
  if message == nil then
    return { body = "unknown error" }
  end

  local filename, linenum, remaining_message = self:_extract_location_from_message(message)
  local header = self:_extract_header(filename, linenum)
  self._parsed_gtest_error = {
    filename = filename,
    linenum = linenum,
    header = header,
    body = remaining_message,
  }
  return self._parsed_gtest_error
end

function Report:_extract_location_from_message(message)
  local linebreak = message:find("\n")
  if linebreak == nil then
    return nil, nil, message
  end
  local first_line = message:sub(1, linebreak - 1)
  local filename, linenum = first_line:match("(.*)%:(%d+)$")
  linenum = linenum and tonumber(linenum)
  return filename, linenum, message:sub(linebreak + 1)
end

function Report:_extract_header(filename, linenum)
  if linenum == nil then
    -- excpetion thrown somewhere
    return nil
  end
  assert(filename ~= nil, "regex either matches both or neither")
  if filename == self._node.path then
    return string.format("Assertion failure at line %d:", linenum)
  else
    return string.format("Assertion failure in %s at line %d:", filename, linenum)
  end
end

function Report:_format_pretty_error_message(parsed_error)
  if parsed_error.header == nil then
    return parsed_error.body
  end
  return table.concat({
    colors().failed,
    colors().bold,
    parsed_error.header,
    colors().stop,
    "\n",
    parsed_error.body,
  })
end

function Report:_build_errors_list()
  if self._errors == nil then
    self._errors = vim.tbl_map(function(e)
      return self:_error_info(e)
    end, self._gtest_json.failures or {})
  end
  return self._errors
end

---@class ReportConverter
---@field _spec neotest.RunSpec
---@field _result neotest.StrategyResult
---@field _tree neotest.Tree
local ReportConverter = {}

---@return ReportConverter
function ReportConverter:new(spec, result, tree)
  local obj = { _spec = spec, _result = result, _tree = tree }
  setmetatable(obj, { __index = self })
  return obj
end

function ReportConverter:make_neotest_results()
  local gtest_json = self:_read_gtest_json()
  local results = {}
  for _, testsuite in ipairs(gtest_json.testsuites) do
    for _, test in ipairs(testsuite.testsuite) do
      local report = Report:new(test, self._tree)
      results[report:position_id()] = report:to_neotest_report(self._result.output)
    end
  end
  self:_notify_if_incomplete_results(results)
  return results
end

function ReportConverter:_notify_if_incomplete_results(results)
  local missing = self:_collect_missing_nodes(results)
  -- TODO printed if we run 2 executables for each one - must aggregate somehow
  -- or filter for things only inside spec
  if #missing > 0 then
    local message = string.format(
      [[Gtest executable %s did not produce results for the following tests: %s. 
      Most likely, the executable for these nodes is not configured correctly.]],
      self._spec.command[1],
      table.concat(missing, ", ")
    )
    vim.notify(message, vim.log.levels.WARN)
  end
end

local function is_leaf_id(id)
  return id:match("%:%:.*%:%:") ~= nil
end

local function is_namespace_id(id)
  return id:match("^[^:]+%:%:[^:]+$") ~= nil
end

local function extract_namespace(id)
  return id:match("^[^:]+%:%:([^:]*)%:%:[^:]+$")
end

function ReportConverter:_collect_missing_nodes(results)
  local missing = {}
  local namespaces = {}
  for node_id, _ in pairs(results) do
    namespaces[extract_namespace(node_id)] = true
  end

  for _, node_id in ipairs(self._spec.context.positions) do
    if is_leaf_id(node_id) and results[node_id] == nil then
      missing[#missing + 1] = node_id
    elseif is_namespace_id(node_id) then
      -- fname::NamespaceId
      local namespace_name = vim.split(node_id, "::")[2]
      if not namespaces[namespace_name] then
        missing[#missing + 1] = node_id
      end
    end
  end
  return missing
end

---@private
function ReportConverter:_read_gtest_json()
  local success, data = pcall(lib.files.read, self._spec.context.results_path)
  if success then
    success, data = pcall(function()
      return vim.json.decode(data) or { testsuites = {} }
    end)
  end
  if not success then
    self:_raise_gtest_failed()
  end

  return data
end

function ReportConverter:_raise_gtest_failed()
  local executable = self._spec.command[1]
  local message
  if utils.fexists(executable) then
    message = string.format(
      [[Gtest executable failed to produce a result. Command: %s, exit code: %d, output at: %s\n
            Please make sure any additional arguments supplied are correct and check the output for additional info.]],
      table.concat(self._spec.command, " "),
      self._result.code,
      self._result.output
    )
  else
    message = string.format([[Gtest executable at path %s not found.]], executable)
  end
  error(message)
end

--TODO: bad name? "converting" spec/result/tree into reports is kind of unintuitive
Report.converter = ReportConverter

return Report
