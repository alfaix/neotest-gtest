local assert = require("luassert")
local nio = require("nio")
local neotest = require("neotest")
neotest.summary = neotest.summary or {}

---@class neotest-gtest.tests.InputMock
---@field private _sync_input fun(...)
---@field private _async_input fun(...)
---@field private _input_value? any
local InputMock = {}

---@return neotest-gtest.tests.InputMock
function InputMock:new()
  local o = { _sync_input = vim.ui.input, _async_input = nio.ui.input, _input_value = nil }
  setmetatable(o, { __index = self })
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.ui.input = function(...)
    return o:input(...)
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  nio.ui.input = nio.tasks.wrap(vim.ui.input, 2)
  return o
end

function InputMock:return_value(value)
  self._input_value = value
end

function InputMock:input(opts, callback)
  self._opts = opts
  callback(self._input_value)
end

function InputMock:revert()
  vim.ui.input = self._sync_input
  nio.ui.input = self._async_input
end

function InputMock:assert_path_requested()
  self:assert_called_with({ prompt = "Enter path to executable:", completion = "file" })
end

function InputMock:assert_path_requested_with_default(default)
  self:assert_called_with({
    prompt = "Enter path to executable:",
    completion = "file",
    default = default,
  })
end

function InputMock:assert_called_with(opts)
  assert.are.same(opts, self._opts)
end

---@class neotest-gtest.tests.MarksMock
---@field private _clear_marks_called boolean
---@field private _mocked_adapter2marks table<string, string[]>
---@field private _old_clear_marked fun(...)
---@field private _old_marked fun(...)
local MarksMock = {}

local function prepend_root_if_needed(adapter2marks)
  for adapter, positions in pairs(adapter2marks) do
    local delimter_index = string.find(adapter, ":")
    local root = string.sub(adapter, delimter_index + 1)
    for i, position in ipairs(positions) do
      if not vim.startswith(position, root) then
        positions[i] = string.format("%s/%s", root, position)
      end
    end
  end
end

---@return neotest-gtest.tests.MarksMock
function MarksMock:new()
  local obj = {
    _clear_marks_called = false,
    _mocked_adapter2marks = {},
    _old_clear_marked = neotest.summary.clear_marked,
    _old_marked = neotest.summary.marked,
  }
  ---@diagnostic disable-next-line: duplicate-set-field
  neotest.summary.clear_marked = function()
    obj._clear_marks_called = true
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  neotest.summary.marked = function()
    return obj._mocked_adapter2marks
  end
  setmetatable(obj, { __index = self })
  return obj
end

function MarksMock:revert()
  neotest.summary.clear_marked = self._old_clear_marked
  neotest.summary.marked = self._old_marked
end

function MarksMock:set_marked(adapter2marks)
  prepend_root_if_needed(adapter2marks)
  self._mocked_adapter2marks = adapter2marks
end

function MarksMock:assert_marks_cleared()
  assert.is_true(self._clear_marks_called)
end

function MarksMock:assert_marks_not_cleared()
  assert.is_false(self._clear_marks_called)
end

---@class neotest-gtest.tests.SelectMock
---@field private _sync_select fun(...)
---@field private _async_select fun(...)
---@field private _select_value? any
---@field private _opts? table
---@field private _choices? any[]
local SelectMock = {}
function SelectMock:new()
  local o = {
    _sync_select = vim.ui.select,
    _async_select = nio.ui.select,
    _select_value = nil,
    _choices = nil,
    _opts = nil,
  }
  setmetatable(o, { __index = self })
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.select = function(...)
    return o:select(...)
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  nio.ui.select = nio.tasks.wrap(vim.fn.select, 3)
  return o
end

function SelectMock:return_option(value)
  self._select_value = value
end

function SelectMock:assert_called_with(choices, opts)
  assert.are.same(choices, self._choices)
  assert.are.same(opts, self._opts)
end

function SelectMock:assert_called_with_choices(choices)
  local opts = { prompt = "Select executable for marked nodes:" }
  self:assert_called_with(choices, opts)
end

function SelectMock:select(choices, opts, callback)
  self._choices = choices
  self._opts = opts
  if self._select_value ~= nil then
    assert.is_true(vim.tbl_contains(choices, self._select_value))
  end
  callback(self._select_value)
end

function SelectMock:revert()
  vim.fn.select = self._sync_select
  nio.ui.select = self._async_select
end

local M = {}

local components_map = {
  select = SelectMock,
  input = InputMock,
  marks = MarksMock,
}

---@class neotest-gtest.tests.MockUi
---@field private _components string[]
---@field public select neotest-gtest.tests.SelectMock
---@field public input neotest-gtest.tests.InputMock
---@field public marks neotest-gtest.tests.MarksMock
local MockUi = {}

function MockUi:new(components)
  components = components or { "select", "input", "marks" }
  local obj = { _components = components }
  for _, component in ipairs(components) do
    obj[component] = components_map[component]:new()
  end
  setmetatable(obj, { __index = self })
  return obj
end

function MockUi:revert()
  for _, component in ipairs(self._components) do
    self[component]:revert()
  end
end

---@return neotest-gtest.tests.MockUi
function M.mock_ui(components)
  return MockUi:new(components)
end

return M
