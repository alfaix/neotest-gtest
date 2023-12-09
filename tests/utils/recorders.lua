local assert = require("luassert")
local neotest_gtest = require("neotest-gtest")
local utils = require("neotest-gtest.utils")
local nio = require("nio")

---@class neotest-gtest.SpecsRecorder
---@field _last_specs? neotest.RunSpec[]
---@field _specs_built nio.control.Event
---@field self._error
local SpecsRecorder = {}

function SpecsRecorder:new()
  local obj = { _specs_built = nio.control.event() }
  setmetatable(obj, { __index = self })
  obj:_setup()
  return obj
end

function SpecsRecorder:_setup()
  local build_spec_fn = neotest_gtest.build_spec
  ---@diagnostic disable-next-line: duplicate-set-field
  neotest_gtest.build_spec = function(args)
    local ok, specs_or_error = pcall(build_spec_fn, args)
    if ok then
      self._last_built_specs = specs_or_error
      self._specs_built.set()
      return specs_or_error
    else
      self._error = specs_or_error
      self._specs_built.set()
      error(specs_or_error)
    end
  end
end

function SpecsRecorder:await_error()
  self._specs_built.wait()
  if self._error then
    return self._error
  end
  error("Expected error, got specs instead: " .. vim.inspect(self._last_built_specs))
end

function SpecsRecorder:await_specs()
  self._specs_built.wait()
  if self._error then
    error(self._error)
  end
  return self._last_built_specs
end

function SpecsRecorder:reset()
  self._last_built_specs = nil
  self._specs_built.clear()
  self._error = nil
end

---@class neotest-gtest.ResultsRecorder
---@field _calls table[]
---@field _expected_calls integer
---@field _all_calls_complete nio.control.Event
local ResultsRecorder = {}

---@return neotest-gtest.ResultsRecorder
function ResultsRecorder:new()
  local obj = {
    _all_calls_complete = nio.control.event(),
    _expected_calls = 1,
    _calls = {},
  }
  setmetatable(obj, { __index = self })
  obj:_setup()
  return obj
end

function ResultsRecorder:_setup()
  local results_fn = neotest_gtest.results
  ---@diagnostic disable-next-line: duplicate-set-field
  neotest_gtest.results = function(spec, result, tree)
    local ok, reports_or_error = pcall(results_fn, spec, result, tree)
    local call
    if ok then
      call = { results = reports_or_error, output_file = result.output }
    else
      call = { error = reports_or_error }
    end
    self._calls[#self._calls + 1] = call
    if #self._calls == self._expected_calls then
      self._all_calls_complete.set()
    end
    if ok then
      -- neotest modifies the resulting table - we only want to assert on our own output
      return utils.tbl_copy(call.results)
    else
      error(call.error)
    end
  end
end

function ResultsRecorder:expect_calls(n)
  self._expected_calls = n
end

function ResultsRecorder:list_calls()
  self._all_calls_complete.wait()
  return utils.tbl_copy(self._calls)
end

function ResultsRecorder:get_aggregated_results()
  local calls = self:list_calls()
  local results = {}
  local position2output = {}
  for _, call in ipairs(calls) do
    assert.is_nil(call.error)
    for position, result in pairs(call.results) do
      assert.is_nil(results[position])
      results[position] = result
      position2output[position] = call.output_file
    end
  end
  return results, position2output
end

function ResultsRecorder:get_last_call()
  self._all_calls_complete.wait()
  return self._calls[1]
end

function ResultsRecorder:reset()
  self._calls = {}
  self._expected_calls = 1

  self._all_calls_complete.clear()
end

return {
  specs = SpecsRecorder,
  results = ResultsRecorder,
}
