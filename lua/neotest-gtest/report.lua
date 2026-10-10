local utils = require("neotest-gtest.utils")
local lib = require("neotest.lib")
local config = require("neotest-gtest.config")

---@class neotest-gtest.Report
---@field _node neotest.Tree
---@field _gtest_json table
local Report = {}

local function colors()
  return config.summary_view.shell_palette
end

---@param gtest_data table
---@param node neotest.Tree
---@return neotest-gtest.Report
function Report:new(gtest_data, node)
  local obj = { _gtest_json = gtest_data, _node = node }
  setmetatable(obj, { __index = self })
  return obj
end

function Report:position_id()
  return self._node:data().id
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

  if parsed_error.linenum ~= nil and parsed_error.filename == self._node:data().path then
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
  if filename == self._node:data().path then
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
  local results, unknown = {}, {}

  for _, testsuite in ipairs(gtest_json and gtest_json.testsuites or {}) do
    for _, test in ipairs(testsuite.testsuite) do
      local node = self:_find_node_by_name(testsuite.name, test.name)
      if node == nil then
        unknown[#unknown + 1] = testsuite.name .. "." .. test.name
      else
        local report = Report:new(test, node)
        local id = node:data().id
        local result = report:to_neotest_report(self._result.output)
        local runtime_name = testsuite.name .. "." .. test.name
        local runtime_id = id .. "::" .. runtime_name
        local runtime_node = self._tree:get_key(runtime_id)
        local kind = node:data().extra and node:data().extra.kind
        local is_generated = kind == "TEST_P" or kind == "TYPED_TEST" or kind == "TYPED_TEST_P"

        if runtime_node then
          results[runtime_id] = Report:new(test, runtime_node)
            :to_neotest_report(self._result.output)
        elseif self._spec.context.position_ids and is_generated and #node:children() > 0 then
          unknown[#unknown + 1] = runtime_name
          result.status = "failed"
          result.short = result.short .. "\nRuntime case has no position: " .. runtime_name
          result.errors[#result.errors + 1] = {
            message = "Runtime case has no position: " .. runtime_name,
          }
        end

        if results[id] then
          local previous = results[id]
          if result.status == "failed" or previous.status == "failed" then
            previous.status = "failed"
          elseif result.status == "passed" then
            previous.status = "passed"
          end
          previous.short = previous.short .. "\n\n" .. result.short
          vim.list_extend(previous.errors, result.errors)
        else
          results[id] = result
        end
      end
    end
  end

  if gtest_json == nil or (self._result.code ~= 0 and self._result.code ~= 1) then
    self:_fail_unreported_positions(results, gtest_json == nil)
  end

  self:_notify_if_unknown_results(unknown)
  self:_notify_if_incomplete_results(results)

  return results
end

function ReportConverter:_fail_unreported_positions(results, missing_json)
  local selected = self._spec.context.position_ids
  if not selected then
    return
  end

  local reason
  if missing_json then
    reason = string.format(
      "Gtest executable failed to produce a result (exit code: %s)",
      self._result.code
    )
  else
    reason =
      string.format("Gtest executable did not report this case (exit code: %s)", self._result.code)
  end

  local function fail_node(node)
    local data = node:data()
    if data.type == "test" and not results[data.id] then
      local message = reason .. ": " .. (data.extra and data.extra.runtime_name or data.id)
      results[data.id] = {
        status = "failed",
        output = self._result.output,
        short = message,
        errors = { { message = message } },
      }
    end

    for _, child in ipairs(node:children()) do
      fail_node(child)
    end
  end

  for _, id in ipairs(selected) do
    local node = self._tree:get_key(id)
    if node then
      fail_node(node)
    end
  end

  if not missing_json and self._result.code ~= 0 and self._result.code ~= 1 then
    for _, id in ipairs(selected) do
      local node = self._tree:get_key(id)
      if node then
        local message = string.format(
          "Gtest executable exited with code %s after writing results: %s",
          self._result.code,
          id
        )
        local result = results[id]

        if result then
          result.status = "failed"
          result.short = result.short .. "\n\n" .. message
          result.errors[#result.errors + 1] = { message = message }
        else
          results[id] = {
            status = "failed",
            output = self._result.output,
            short = message,
            errors = { { message = message } },
          }
        end

        local parent = node:parent()
        while parent do
          if results[parent:data().id] then
            results[parent:data().id].status = "failed"
          end
          parent = parent:parent()
        end
      end
    end
  end

  -- A source position also reports the combined status of its runtime leaves.
  for _, id in ipairs(selected) do
    local node = self._tree:get_key(id)
    if node then
      for _, descendant in node:iter_nodes() do
        local data = descendant:data()
        if data.extra and data.extra.runtime_name then
          local parent_id = descendant:parent():data().id
          local parent = results[parent_id]
          if parent and results[data.id] and results[data.id].status == "failed" then
            parent.status = "failed"
            if not parent.short:find(results[data.id].short, 1, true) then
              parent.short = parent.short .. "\n\n" .. results[data.id].short
              vim.list_extend(parent.errors, results[data.id].errors)
            end
          end
        end
      end
    end
  end
end

function ReportConverter:_find_node_by_name(namespace, name)
  local ctx = assert(self._spec.context, "context must not be nil")
  local source_namespace = namespace
  local source_name = name
  local fpath
  local runtime_name = namespace .. "." .. name
  if ctx.name2path[runtime_name] then
    fpath = ctx.name2path[runtime_name]
  elseif ctx.name2path[namespace] then
    fpath = ctx.name2path[namespace]
  elseif ctx.name2path[namespace .. "." .. name] then
    fpath = ctx.name2path[namespace .. "." .. name]
  end

  if name:find("/", 1, true) then
    source_namespace = namespace:match(".*/([^/]+)$") or namespace
    source_name = name:match("^([^/]+)/[^/]+$") or name
  elseif namespace:find("/", 1, true) then
    source_namespace = namespace:match("([^/]+)/[^/]+$") or namespace
  end

  if fpath == nil then
    fpath = ctx.name2path[source_namespace .. "." .. source_name] or ctx.name2path[source_namespace]
  end

  if fpath == nil then
    return nil
  end

  local node_id = table.concat({ fpath, source_namespace, source_name }, "::")
  local node = self._tree:get_key(node_id)
  if source_namespace ~= namespace or source_name ~= name then
    local kind = node and node:data().extra and node:data().extra.kind
    if kind ~= "TEST_P" and kind ~= "TYPED_TEST" and kind ~= "TYPED_TEST_P" then
      return nil
    end
  end
  return node
end

function ReportConverter:_notify_if_unknown_results(unknown)
  if #unknown == 0 then
    return
  end
  utils.schedule_notify(
    string.format(
      "%s ran %d test(s) with no position in the source tree (treesitter could not parse them?): %s",
      self._spec.command[1],
      #unknown,
      table.concat(unknown, ", ")
    ),
    vim.log.levels.WARN
  )
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
    utils.schedule_notify(message, vim.log.levels.WARN)
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
    if node_id ~= nil then
      local namespace = extract_namespace(node_id)
      if namespace ~= nil then
        namespaces[extract_namespace(node_id)] = true
      end
    end
  end

  for name, fpath in pairs(self._spec.context.name2path) do
    if not name:find("/", 1, true) then
      local node_id = fpath .. "::" .. string.gsub(name, "%.", "::")
      if is_namespace_id(node_id) then
        if not namespaces[name] then
          missing[#missing + 1] = node_id
        end
      elseif is_leaf_id(node_id) and results[node_id] == nil then
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
    if not utils.fexists(self._spec.command[1]) then
      self:_raise_gtest_failed()
    end
    if self._spec.context.position_ids then
      return nil
    end
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
  utils.schedule_error(message)
end

--TODO: bad name? "converting" spec/result/tree into reports is kind of unintuitive
Report.converter = ReportConverter

return Report
