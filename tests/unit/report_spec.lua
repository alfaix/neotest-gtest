local lib = require("neotest.lib")
local assert = require("luassert")
local Report = require("neotest-gtest.report")
local helpers = require("tests.utils.helpers")
local config = require("neotest-gtest.config")
local tree_utils = require("tests.utils.tree")

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

local colors = config.summary_view.shell_palette
local header_length = config.summary_view.header_length
local function assert_header_matches_spec(header, spec)
  local expected_color = colors[spec.status] .. colors.bold
  assert.is_not_nil(expected_color)
  local pattern = "^([^_]*)%_+(%a+)%.(%a+)%_+([^_]+)"
  local color, namespace, name, color_stop = string.match(header, pattern)
  assert.are.same(#header - #color - #color_stop, header_length, header)
  assert.are.same(expected_color, color)
  assert.are.same(namespace, spec.namespace)
  assert.are.same(name, spec.name)
  assert.are.same(colors.stop, color_stop)
end

local function assert_body_matches_spec(body, spec)
  spec.summary = helpers.string_replace(spec.summary, "{TIMESTAMP}", TEST_TIMESTAMP)
  spec.summary = helpers.dedent(spec.summary)

  body = helpers.string_replace(body, colors.bold, "{BOLD}")
  body = helpers.string_replace(body, colors.failed, "{RED}")
  body = helpers.string_replace(body, colors.passed, "{GREEN}")
  body = helpers.string_replace(body, colors.stop, "{STOP}")
  -- assert.are.same({ string.byte(spec.summary, 0, #spec.summary) }, { string.byte(body, 0, #body) })
  assert.are.same(spec.summary, body)
end

local function assert_summary_matches_spec(summary, spec)
  local lineend = string.find(summary, "\n", 1, true)
  local header = summary:sub(1, lineend - 1)
  local body = summary:sub(lineend + 1)
  assert_header_matches_spec(header, spec)
  assert_body_matches_spec(body, spec)
end

local function assert_errors_match_spec(errors, spec)
  spec.errors = spec.errors or {}
  local cmp = function(a, b)
    return a.message < b.message
  end
  table.sort(errors, cmp)
  table.sort(spec.errors, cmp)

  for i, error in ipairs(errors) do
    assert.are.same(spec.errors[i].message, error.message)
    assert.are.same(spec.errors[i].line, error.line)
  end
end

local function assert_neotest_reulst_matches_spec(result, spec)
  assert.are.same(spec.status, result.status)
  assert.are.same(MOCK_OUTPUT_FILE, result.output)
  assert_summary_matches_spec(result.short, spec)
  assert_errors_match_spec(result.errors, spec)
end

local function assert_report_matches_spec(report, spec)
  local id = table.concat({ FILENAME, spec.namespace, spec.name }, "::")
  assert.are.same(id, report:position_id())

  local neotest_report = report:to_neotest_report(MOCK_OUTPUT_FILE)
  assert_neotest_reulst_matches_spec(neotest_report, spec)
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
      local report = results[key]
      assert_neotest_reulst_matches_spec(report, spec)
    end
  end

  it("builder happy path creates correct reports", function()
    setup()
    local run_spec = {
      command = { "/some-command" },
      context = { results_path = json_path },
    }
    local neotest_result = {
      code = 0,
      output = MOCK_OUTPUT_FILE,
    }
    local converter = Report.converter:new(run_spec, neotest_result, tree)
    local results = converter:make_neotest_results()
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
    local run_spec = {
      command = { "/some-command" },
      context = { results_path = "/doesntexist" },
    }
    local neotest_result = {
      code = 1,
      output = "/somepath",
    }
    local converter = Report.converter:new(run_spec, neotest_result, tree)
    local ok, message = pcall(function()
      converter:make_neotest_results()
    end)
    assert.is_false(ok)
    assert(message) -- appease the type checker
    assert.is_not_nil(
      string.find(message, "Command: /some-command, exit code: 1, output at: /somepath", 1, true)
    )
  end)
end)
