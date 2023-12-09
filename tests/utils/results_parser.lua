local ReportSpec = require("tests.utils.report")
local helpers = require("tests.utils.helpers")
local nio = require("nio")
local assert = require("luassert")
local files = require("neotest.lib").files
local ts_lib = require("neotest.lib").treesitter

local COMMENTS_QUERY = vim.treesitter.query.parse("cpp", "(comment) @comment")
---@class ResultsParser
---@field _filepath string
---@field _current_id string
---@field _parsed table<string, any>
local Parser = {}

---@return ResultsParser
function Parser:new(filepath)
  local obj = { _filepath = filepath, _current_id = nil, _parsed = {} }
  setmetatable(obj, self)
  self.__index = self
  return obj
end

---@return table<string, neotest-gtest.tests.ReportSpec>
function Parser:parse_report_specs()
  if not vim.tbl_isempty(self._parsed) then
    return self._parsed
  end

  local comments = self:_list_comments()
  for _, comment in ipairs(comments) do
    self:_parse_comment(comment)
  end
  return vim.tbl_map(function(parsed)
    return ReportSpec:new(parsed)
  end, self._parsed)
end

function Parser:_list_comments()
  local content = files.read(self._filepath)
  local lang_tree = vim.treesitter.get_string_parser(content, "cpp", nil)
  local treesitter_tree = ts_lib.fast_parse(lang_tree):root()
  local comments = {}
  for _, node, _ in COMMENTS_QUERY:iter_captures(treesitter_tree, content, 0, -1) do
    local comment_text = vim.treesitter.get_node_text(node, content)
    local range = { node:range() }
    comments[#comments + 1] = {
      text = self:_extract_comment_content(comment_text),
      line = range[1],
    }
  end
  return comments
end

function Parser:_extract_comment_content(comment)
  if vim.startswith(comment, "//") then
    return vim.trim(comment:sub(3))
  else
    assert(vim.startswith(comment, "/*") and vim.endswith(comment, "*/"))
    return vim.trim(comment:sub(3, -3))
  end
end

function Parser:_parse_comment(comment)
  if vim.startswith(comment.text, "NODE:") then
    self:_add_node(comment)
  elseif comment.text == "NODEEND" then
    self._parsed[self._current_id].last = comment.line
  elseif vim.startswith(comment.text, "MESSAGE:") then
    self:_add_message(comment)
  end
end

-- expected format: NODE:<Namespace::Name>,<TestResult>
function Parser:_add_node(comment)
  local namespace, name, status = comment.text:match("^NODE%:*([^:]+)::([^,]+),(.+)$")
  local parsed = {
    id = self:_prepend_filename(namespace .. "::" .. name),
    filename = self._filepath,
    namespace = namespace,
    name = name,
    status = status,
    output_file = nil,
    summary = "MATCH_ERRORS_ONLY",
    first = comment.line,
  }
  self._parsed[parsed.id] = vim.tbl_extend("error", self._parsed[parsed.id] or {}, parsed)
  self._current_id = parsed.id
end

function Parser:_add_message(comment)
  local id, message = self:_parse_error(comment)
  assert.is_not_nil(id)
  if not self._parsed[id] then
    self._parsed[id] = { errors = { message } }
  elseif not self._parsed[id].errors then
    self._parsed[id].errors = { message }
  else
    table.insert(self._parsed[id].errors, message)
  end
end

---@return string, neotest.Error
function Parser:_parse_error(comment)
  local regex = "^MESSAGE:\\(\\S\\+\\)\\?\\n\\(\\_.\\+\\)$"
  local groups = nio.fn.matchlist(comment.text, regex, 0, nil)
  local id
  local line
  if vim.startswith(groups[2], "NOLINE") then
    groups[2] = groups[2]:sub(7)
    line = nil
  else
    line = comment.line
  end
  if groups[2] == "" then
    id = self._current_id
  else
    id = self:_prepend_filename(groups[2])
  end
  local message = {
    message = helpers.dedent(groups[3]),
    line = line,
  }
  return id, message
end

function Parser:_prepend_filename(node_id)
  return self._filepath .. "::" .. node_id
end
return Parser
