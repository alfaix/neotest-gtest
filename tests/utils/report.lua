local helpers = require("tests.utils.helpers")
local assert = require("luassert")
local utils = require("neotest-gtest.utils")
local config = require("neotest-gtest.config")

local colors = config.summary_view.shell_palette
local header_length = config.summary_view.header_length

---@class neotest-gtest.tests.ReportSpec
---@field id? string
---@field filename string
---@field namespace string
---@field name string
---@field status string
---@field output_file string
---@field summary string
---@field timestamp string
---@field errors? neotest.Error[]
local ReportSpec = {}

---@param opts neotest-gtest.tests.ReportSpec
---@return neotest-gtest.tests.ReportSpec
function ReportSpec:new(opts)
  local o = utils.tbl_copy(opts)
  setmetatable(o, self)
  self.__index = self
  return o
end

---@param report neotest-gtest.Report
function ReportSpec:assert_matches_report(report)
  local id = self.id or table.concat({ self.filename, self.namespace, self.name }, "::")
  assert.are.same(id, report:position_id())

  local neotest_report = report:to_neotest_report(self.output_file)
  self:assert_matches_neotest_result(neotest_report)
end

---@param neotest_result neotest.Result
function ReportSpec:assert_matches_neotest_result(neotest_result)
  self._result = neotest_result
  assert.is_not_nil(neotest_result)
  assert.are.same(self.output_file, neotest_result.output)
  assert.are.same(self.status, neotest_result.status)
  self:_assert_matches_summary(neotest_result.short)
  self:_assert_matches_errors(neotest_result.errors)
end

function ReportSpec:_assert_matches_errors(errors)
  self.errors = self.errors or {}
  local cmp = function(a, b)
    return a.line < b.line
  end
  table.sort(errors, cmp)
  table.sort(self.errors, cmp)
  if #self.errors ~= #errors then
    error(vim.inspect(self))
  end
  assert.are.equal(#self.errors, #errors)

  for i, err in ipairs(self.errors) do
    assert.are.same(self.errors[i].message, err.message)
    assert.are.same(self.errors[i].line, err.line)
  end
end

function ReportSpec:_assert_matches_summary(summary)
  local lineend = string.find(summary, "\n", 1, true)
  local header = summary:sub(1, lineend - 1)
  local body = summary:sub(lineend + 1)
  self:_assert_matches_header(header)
  self:_assert_matches_body(body)
end

function ReportSpec:_assert_matches_header(header)
  local expected_color = colors[self.status] .. colors.bold
  assert.is_not_nil(expected_color)
  local pattern = "^([^_]*)%_+(%a+)%.(%a+)%_+([^_]+)"
  local color, namespace, name, color_stop = string.match(header, pattern)
  assert.are.same(#header - #color - #color_stop, header_length, header)
  assert.are.same(expected_color, color)
  assert.are.same(namespace, self.namespace)
  assert.are.same(name, self.name)
  assert.are.same(colors.stop, color_stop)
end

function ReportSpec:_assert_matches_body(body)
  if self.summary == "MATCH_ERRORS_ONLY" then
    for _, err in ipairs(self.errors or {}) do
      if not string.find(body, err.message, 1, true) then
        error(vim.inspect({ self }))
      end
      assert.is_not_nil(string.find(body, err.message, 1, true))
    end
    return
  end
  self.summary = helpers.string_replace(self.summary, "{TIMESTAMP}", self.timestamp)
  self.summary = helpers.dedent(self.summary)

  body = helpers.string_replace(body, colors.bold, "{BOLD}")
  body = helpers.string_replace(body, colors.failed, "{RED}")
  body = helpers.string_replace(body, colors.passed, "{GREEN}")
  body = helpers.string_replace(body, colors.stop, "{STOP}")
  assert.are.same(self.summary, body)
end

return ReportSpec
