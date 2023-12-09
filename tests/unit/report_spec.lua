local utils = require("neotest-gtest.utils")
local lib = require("neotest.lib")
local assert = require("luassert")
local Report = require("neotest-gtest.report")
local tree_utils = require("tests.utils.tree")
local ReportSpec = require("tests.utils.report")

local TEST_TIMESTAMP = "2023-01-01T00:00:00Z"
local FILENAME = "/test_one.cpp"
local MOCK_OUTPUT_FILE = "123"

local default_gtest_report = {
  ["name"] = "TestFoo",
  ["file"] = FILENAME,
  ["line"] = 1, -- ignored
  ["status"] = "RUN",
  ["result"] = "COMPLETED",
  ["timestamp"] = TEST_TIMESTAMP,
  ["time"] = "0s",
  ["classname"] = "TestOne",
  ["failures"] = {},
}

local make_gtest_report = function(spec)
  return vim.tbl_extend("force", default_gtest_report, spec)
end

local function tree_with_data(id, data)
  return {
    get_key = function(_self, _id)
      assert.are.same(id, _id)
      return {
        data = function()
          return data
        end,
      }
    end,
  }
end

local function _enrich_spec(spec)
  spec = utils.tbl_copy(spec)
  spec.filename = FILENAME
  spec.timestamp = TEST_TIMESTAMP
  spec.output_file = MOCK_OUTPUT_FILE
  return spec
end

local function assert_report_matches_spec(report, spec)
  spec = _enrich_spec(spec)
  local report_spec = ReportSpec:new(spec)
  report_spec:assert_matches_report(report)
end

describe("report", function()
  local tree = tree_with_data("/test_one.cpp::TestOne::TestFoo", {
    path = FILENAME,
    range = { 0, 0, 0, 0 },
  })
  local test_result

  local function with_result(spec)
    test_result = vim.tbl_extend("force", default_gtest_report, spec)
  end

  local function creates_report(spec)
    spec.name = "TestFoo"
    spec.namespace = "TestOne"
    local report = Report:new(test_result, tree)
    assert_report_matches_spec(report, spec)
  end

  it("successful test produces a successful report", function()
    with_result({ name = "TestFoo" })
    local report = Report:new(test_result, tree)
    assert_report_matches_spec(report, {
      name = "TestFoo",
      namespace = "TestOne",
      status = "passed",
      summary = "Passed, Time: 0s, Timestamp: " .. TEST_TIMESTAMP,
    })
  end)

  it("error within the same test file", function()
    with_result({
      failures = {
        {
          failure = FILENAME .. ":1\nOh no",
          type = "",
        },
      },
    })
    creates_report({
      status = "failed",
      summary = [[
        Errors: 1, Time: 0s, Timestamp: {TIMESTAMP}
        {RED}{BOLD}Assertion failure at line 1:{STOP}
        Oh no
      ]],
      errors = { { message = "Oh no", line = 0 } },
    })
  end)

  it("multiple errors concatenated properly", function()
    with_result({
      failures = {
        {
          failure = FILENAME .. ":1\nOh no",
          type = "",
        },
        {
          failure = FILENAME .. ":2\nOh yes!",
          type = "",
        },
      },
    })
    creates_report({
      status = "failed",
      summary = [[
        Errors: 2, Time: 0s, Timestamp: {TIMESTAMP}
        {RED}{BOLD}Assertion failure at line 1:{STOP}
        Oh no
        {RED}{BOLD}Assertion failure at line 2:{STOP}
        Oh yes!
      ]],
      errors = { { message = "Oh no", line = 0 }, { message = "Oh yes!", line = 1 } },
    })
  end)

  it("error within a different file", function()
    with_result({
      failures = {
        {
          failure = "/some_other_file.cpp:1\nOh no",
          type = "",
        },
      },
    })
    creates_report({
      status = "failed",
      summary = [[
        Errors: 1, Time: 0s, Timestamp: {TIMESTAMP}
        {RED}{BOLD}Assertion failure in /some_other_file.cpp at line 1:{STOP}
        Oh no
      ]],
      errors = { { message = "Oh no", line = nil } },
    })
  end)

  it("error with unknown error format", function()
    with_result({
      failures = {
        {
          failure = "something something",
          type = "",
        },
      },
    })
    creates_report({
      status = "failed",
      summary = [[
        Errors: 1, Time: 0s, Timestamp: {TIMESTAMP}
        something something
      ]],
      errors = { { message = "something something", line = nil } },
    })
  end)

  it("error without any message", function()
    with_result({
      failures = {
        {
          failure = nil,
          type = "",
        },
      },
    })
    creates_report({
      status = "failed",
      summary = [[
        Errors: 1, Time: 0s, Timestamp: {TIMESTAMP}
        unknown error
      ]],
      errors = { { message = "unknown error", line = nil } },
    })
  end)

  it("skipped", function()
    with_result({ result = "SKIPPED" })
    creates_report({
      status = "skipped",
      summary = "Test skipped, Timestamp: {TIMESTAMP}",
    })
  end)

  it("notrun", function()
    with_result({ status = "NOTRUN" })
    creates_report({
      status = "skipped",
      summary = "Test skipped, Timestamp: {TIMESTAMP}",
    })
  end)
end)

local it = require("nio.tests").it
describe("report builder", function()
  local tree
  local dirpath
  local full_gtest_report
  local json_path
  local function setup()
    dirpath = vim.fn.tempname()
    tree = tree_utils.make_directory_tree({
      ["test_one.cpp"] = "TEST(TestOne, Foo) {}",
      ["test_two.cpp"] = "TEST(TestTwo, Bar) {}",
    }, dirpath)
    full_gtest_report = {
      ["testsuites"] = {
        {
          ["name"] = "TestOne",
          ["testsuite"] = {
            make_gtest_report({
              ["name"] = "Foo",
              ["file"] = dirpath .. "/test_one.cpp",
              ["classname"] = "TestOne",
            }),
          },
        },
        {
          ["name"] = "TestTwo",
          ["testsuite"] = {
            make_gtest_report({
              ["name"] = "Bar",
              ["file"] = dirpath .. "/test_two.cpp",
              ["classname"] = "TestTwo",
            }),
          },
        },
      },
    }
    json_path = dirpath .. "/report.json"
    lib.files.write(json_path, vim.fn.json_encode(full_gtest_report))
  end

  local function assert_results_match_spec(results, position2spec)
    local expected_keys = vim.tbl_keys(position2spec)
    local actual_keys = vim.tbl_keys(results)
    table.sort(expected_keys)
    table.sort(actual_keys)
    assert.are.same(expected_keys, actual_keys)
    for _, key in ipairs(expected_keys) do
      local spec = position2spec[key]
      spec.position_id = key
      local neotest_result = results[key]
      spec = ReportSpec:new(_enrich_spec(spec))
      spec:assert_matches_neotest_result(neotest_result)
    end
  end

  local function make_neotest_results(opts)
    local default_opts = {
      command = { "/usr/bin/env" }, -- must exist
      results_path = json_path,
      code = 0,
      output = MOCK_OUTPUT_FILE,
      expect_error = false,
    }
    opts = vim.tbl_extend("force", default_opts, opts or {})

    local converter = Report.converter:new(
      { command = opts.command, context = { results_path = opts.results_path, positions = {} } },
      { code = opts.code, output = opts.output },
      tree
    )
    local ok, message_or_results = pcall(function()
      return converter:make_neotest_results()
    end)
    if opts.expect_error == ok then
      error(vim.inspect(message_or_results))
    end
    assert.are.equal(opts.expect_error, not ok)
    if ok then
      return message_or_results
    else
      return message_or_results
    end
  end

  it("builder happy path creates correct reports", function()
    setup()
    local results = make_neotest_results()
    assert_results_match_spec(results, {
      [dirpath .. "/test_one.cpp::TestOne::Foo"] = {
        name = "Foo",
        namespace = "TestOne",
        status = "passed",
        summary = "Passed, Time: 0s, Timestamp: " .. TEST_TIMESTAMP,
      },
      [dirpath .. "/test_two.cpp::TestTwo::Bar"] = {
        name = "Bar",
        namespace = "TestTwo",
        status = "passed",
        summary = "Passed, Time: 0s, Timestamp: " .. TEST_TIMESTAMP,
      },
    })
  end)

  it("builder throws error if file does not exist", function()
    local message = make_neotest_results({ expect_error = true, results_path = "/doesntexist" })
    ---@cast message string
    local expected = "Command: /usr/bin/env, exit code: 0, output at: " .. MOCK_OUTPUT_FILE
    assert.is_not_nil(string.find(message, expected, 1, true))
  end)

  it("builder throws error if executable does not exist", function()
    local message = make_neotest_results({
      expect_error = true,
      command = { "/doesntexist" },
      results_path = "/doesntexist",
    })
    ---@cast message string
    local expected = "/doesntexist not found"
    assert.is_not_nil(string.find(message, expected, 1, true))
  end)
end)
