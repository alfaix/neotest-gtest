local utils = require("neotest-gtest.utils")
local lib = require("neotest.lib")
local assert = require("luassert")
local Report = require("neotest-gtest.report")
local tree_utils = require("tests.utils.tree")
local ReportSpec = require("tests.utils.report")
local ui_mock = require("tests.utils.ui_mock")

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
  data.id = id
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
    local report = Report:new(test_result, tree:get_key("/test_one.cpp::TestOne::TestFoo"))
    assert_report_matches_spec(report, spec)
  end

  it("successful test produces a successful report", function()
    with_result({ name = "TestFoo" })
    creates_report({
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
      position_ids = nil,
      expect_error = false,
    }
    opts = vim.tbl_extend("force", default_opts, opts or {})

    local converter = Report.converter:new({
      command = opts.command,
      context = {
        results_path = opts.results_path,
        positions = {},
        name2path = opts.name2path or {
          ["TestOne"] = dirpath .. "/test_one.cpp",
          ["TestOne.Foo"] = dirpath .. "/test_one.cpp",
          ["TestTwo"] = dirpath .. "/test_two.cpp",
          ["TestTwo.Bar"] = dirpath .. "/test_two.cpp",
        },
        position_ids = opts.position_ids,
      },
    }, { code = opts.code, output = opts.output }, tree)
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

  local function parameterized_tree(runtime_names)
    local source_file = dirpath .. "/test_one.cpp"
    local source_id = source_file .. "::TestOne::Foo"
    local parse = require("neotest-gtest.parse")
    lib.files.write(source_file, "TEST_P(TestOne, Foo) {}")

    tree = parse.parse_positions(source_file, {
      [source_id] = runtime_names,
    })

    return source_id
  end

  local function write_parameterized_results(cases)
    local suites = {}
    for _, case in ipairs(cases) do
      local suite, name = case.full_name:match("^([^%.]+)%.(.+)$")
      suites[#suites + 1] = {
        name = suite,
        testsuite = {
          make_gtest_report({
            name = name,
            classname = suite,
            failures = case.failures or {},
            result = case.result or "COMPLETED",
          }),
        },
      }
    end

    lib.files.write(json_path, vim.json.encode({ testsuites = suites }))
  end

  it("reports pass, fail, and skip on separate runtime leaves and fails the parent", function()
    setup()
    local names = { "First/TestOne.Foo/0", "First/TestOne.Foo/1", "Second/TestOne.Foo/0" }
    local source_id = parameterized_tree(names)
    write_parameterized_results({
      { full_name = names[1] },
      {
        full_name = names[2],
        failures = {
          { failure = dirpath .. "/test_one.cpp:3\nexpected true, got false", type = "" },
        },
      },
      { full_name = names[3], result = "SKIPPED" },
    })

    local results = make_neotest_results({
      name2path = { ["TestOne.Foo"] = dirpath .. "/test_one.cpp" },
      position_ids = { source_id },
    })

    assert.equals("passed", results[source_id .. "::" .. names[1]].status)
    assert.equals("failed", results[source_id .. "::" .. names[2]].status)
    assert.equals("skipped", results[source_id .. "::" .. names[3]].status)
    assert.equals("failed", results[source_id].status)
    assert.equals(2, results[source_id .. "::" .. names[2]].errors[1].line)
    assert.matches(
      "expected true, got false",
      results[source_id .. "::" .. names[2]].short,
      1,
      true
    )
    assert.same({}, results[source_id .. "::" .. names[1]].errors)
  end)

  it("reports typed cases by their full runtime names", function()
    setup()
    local source_file = dirpath .. "/test_one.cpp"
    local source_id = source_file .. "::TypedFixture::Works"
    local names = { "TypedFixture/Small.Works", "TypedFixture/Large.Works" }
    local parse = require("neotest-gtest.parse")

    lib.files.write(source_file, "TYPED_TEST(TypedFixture, Works) {}")
    tree = parse.parse_positions(source_file, { [source_id] = names })
    write_parameterized_results({
      { full_name = names[1] },
      {
        full_name = names[2],
        failures = { { failure = source_file .. ":1\ntyped failure", type = "" } },
      },
    })

    local results = make_neotest_results({
      name2path = { ["TypedFixture.Works"] = source_file },
      position_ids = { source_id },
    })

    assert.equals("passed", results[source_id .. "::" .. names[1]].status)
    assert.equals("failed", results[source_id .. "::" .. names[2]].status)
    assert.equals("failed", results[source_id].status)
    assert.equals("typed failure", results[source_id .. "::" .. names[2]].errors[1].message)
    assert.equals(0, results[source_id .. "::" .. names[2]].errors[1].line)
  end)

  it("reports type-parameterized cases from separate instantiations", function()
    setup()
    local source_file = dirpath .. "/test_one.cpp"
    local source_id = source_file .. "::PatternFixture::Works"
    local names = {
      "First/PatternFixture/0.Works",
      "Second/PatternFixture/0.Works",
    }
    local parse = require("neotest-gtest.parse")

    lib.files.write(source_file, "TYPED_TEST_P(PatternFixture, Works) {}")
    tree = parse.parse_positions(source_file, { [source_id] = names })
    write_parameterized_results({
      { full_name = names[1] },
      {
        full_name = names[2],
        failures = { { failure = source_file .. ":1\ntype pattern failed", type = "" } },
      },
    })

    local results = make_neotest_results({
      name2path = { ["PatternFixture.Works"] = source_file },
      position_ids = { source_id },
    })

    assert.equals("passed", results[source_id .. "::" .. names[1]].status)
    assert.equals("failed", results[source_id .. "::" .. names[2]].status)
    assert.equals("failed", results[source_id].status)
    assert.equals("type pattern failed", results[source_id .. "::" .. names[2]].errors[1].message)
    assert.equals(0, results[source_id .. "::" .. names[2]].errors[1].line)
  end)

  it("fails selected runtime leaves when the JSON report is missing", function()
    setup()
    local name = "First/TestOne.Foo/0"
    local source_id = parameterized_tree({ name })

    local results = make_neotest_results({
      results_path = dirpath .. "/missing.json",
      name2path = { ["TestOne.Foo"] = dirpath .. "/test_one.cpp" },
      position_ids = { source_id .. "::" .. name },
    })

    assert.equals("failed", results[source_id .. "::" .. name].status)
    assert.matches("result", results[source_id .. "::" .. name].errors[1].message)
  end)

  it("fails unreported runtime leaves when the process crashes after partial JSON", function()
    setup()
    local names = { "First/TestOne.Foo/0", "First/TestOne.Foo/1" }
    local source_id = parameterized_tree(names)
    write_parameterized_results({ { full_name = names[1] } })

    local results = make_neotest_results({
      code = 139,
      name2path = { ["TestOne.Foo"] = dirpath .. "/test_one.cpp" },
      position_ids = { source_id },
    })

    assert.equals("passed", results[source_id .. "::" .. names[1]].status)
    assert.equals("failed", results[source_id .. "::" .. names[2]].status)
    assert.equals("failed", results[source_id].status)
    assert.matches("139", results[source_id .. "::" .. names[2]].errors[1].message)
  end)

  it("fails a selected leaf when the process crashes after writing a passing report", function()
    setup()
    local name = "First/TestOne.Foo/0"
    local source_id = parameterized_tree({ name })
    write_parameterized_results({ { full_name = name } })

    local results = make_neotest_results({
      code = 139,
      name2path = { ["TestOne.Foo"] = dirpath .. "/test_one.cpp" },
      position_ids = { source_id .. "::" .. name },
    })

    assert.equals("failed", results[source_id .. "::" .. name].status)
    assert.matches("139", results[source_id .. "::" .. name].errors[1].message)
  end)

  it("fails a selected source when the process crashes after writing passing reports", function()
    setup()
    local name = "First/TestOne.Foo/0"
    local source_id = parameterized_tree({ name })
    write_parameterized_results({ { full_name = name } })

    local results = make_neotest_results({
      code = 139,
      name2path = { ["TestOne.Foo"] = dirpath .. "/test_one.cpp" },
      position_ids = { source_id },
    })

    assert.equals("failed", results[source_id].status)
    assert.matches("139", results[source_id].errors[1].message)
    assert.equals("passed", results[source_id .. "::" .. name].status)
  end)

  it("diagnoses a returned runtime case that has no position", function()
    setup()
    local name = "First/TestOne.Foo/Unexpected"
    local source_id = parameterized_tree({ "First/TestOne.Foo/0" })
    write_parameterized_results({ { full_name = name } })
    local notifications = ui_mock.NotificationsMock:new()

    local results = make_neotest_results({
      name2path = { ["TestOne.Foo"] = dirpath .. "/test_one.cpp" },
      position_ids = { source_id },
    })
    notifications:revert()

    assert.is_nil(results[source_id .. "::" .. name])
    notifications:assert_notified(name, vim.log.levels.WARN)
    assert.equals("failed", results[source_id].status)
    assert.matches("Runtime case has no position", results[source_id].errors[1].message)
  end)

  it("warns when a returned runtime suite has no source mapping", function()
    setup()
    local source_id = parameterized_tree({ "First/TestOne.Foo/0" })
    local unknown_name = "Other/Unexpected.Case/0"
    write_parameterized_results({ { full_name = unknown_name } })
    local notifications = ui_mock.NotificationsMock:new()

    local results = make_neotest_results({
      name2path = { ["TestOne.Foo"] = dirpath .. "/test_one.cpp" },
      position_ids = { source_id },
    })
    notifications:revert()

    assert.is_nil(results[source_id])
    notifications:assert_notified(unknown_name, vim.log.levels.WARN)
  end)

  it("keeps duplicate runtime names from different executable mappings separate", function()
    setup()
    local runtime_name = "Same/TestOne.Foo/0"
    local first_file = dirpath .. "/test_one.cpp"
    local second_file = dirpath .. "/test_two.cpp"
    local first_id = first_file .. "::TestOne::Foo"
    local second_id = second_file .. "::TestOne::Foo"
    local parse = require("neotest-gtest.parse")
    lib.files.write(first_file, "TEST_P(TestOne, Foo) {}")
    lib.files.write(second_file, "TEST_P(TestOne, Foo) {}")

    tree = parse.parse_positions(first_file, { [first_id] = { runtime_name } })
    write_parameterized_results({ { full_name = runtime_name } })
    local first_results = make_neotest_results({
      name2path = { [runtime_name] = first_file, ["TestOne.Foo"] = first_file },
      position_ids = { first_id },
    })

    tree = parse.parse_positions(second_file, { [second_id] = { runtime_name } })
    write_parameterized_results({
      {
        full_name = runtime_name,
        failures = { { failure = second_file .. ":1\nsecond executable failed", type = "" } },
      },
    })
    local second_results = make_neotest_results({
      name2path = { [runtime_name] = second_file, ["TestOne.Foo"] = first_file },
      position_ids = { second_id },
    })

    assert.equals("passed", first_results[first_id .. "::" .. runtime_name].status)
    assert.is_nil(first_results[second_id .. "::" .. runtime_name])
    assert.equals("failed", second_results[second_id .. "::" .. runtime_name].status)
    assert.is_nil(second_results[first_id .. "::" .. runtime_name])
  end)

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

  it("combines parameterized instances at their source position", function()
    setup()
    tree = tree_utils.make_directory_tree({
      ["test_one.cpp"] = "TEST_P(TestOne, Foo) {}",
    }, dirpath)
    full_gtest_report.testsuites = {
      {
        name = "First/TestOne",
        testsuite = {
          make_gtest_report({
            name = "Foo/0",
            classname = "First/TestOne",
            failures = {},
          }),
        },
      },
      {
        name = "Second/TestOne",
        testsuite = {
          make_gtest_report({
            name = "Foo/1",
            classname = "Second/TestOne",
            failures = { { failure = FILENAME .. ":1\nBroken", type = "" } },
          }),
        },
      },
      {
        name = "TestOne",
        testsuite = {
          make_gtest_report({
            name = "Foo/2",
            classname = "TestOne",
            failures = {},
          }),
        },
      },
    }
    lib.files.write(json_path, vim.json.encode(full_gtest_report))

    local results = make_neotest_results({
      name2path = { ["TestOne.Foo"] = dirpath .. "/test_one.cpp" },
    })
    local result = results[dirpath .. "/test_one.cpp::TestOne::Foo"]
    assert.is_not_nil(result)
    assert.are.equal("failed", result.status)
    assert.is_not_nil(result.short:find("First/TestOne.Foo/0", 1, true))
    assert.is_not_nil(result.short:find("Second/TestOne.Foo/1", 1, true))
    assert.is_not_nil(result.short:find("TestOne.Foo/2", 1, true))
    assert.are.equal("Broken", result.errors[1].message)
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

  it("builder skips tests without a position and warns about them", function()
    setup()
    -- Same suite as a parsed test, but no TEST() in the tree: what a treesitter
    -- parse failure in the source produces once the binary runs Suite.*
    table.insert(
      full_gtest_report.testsuites[1].testsuite,
      make_gtest_report({
        ["name"] = "Unparsed",
        ["file"] = dirpath .. "/test_one.cpp",
        ["classname"] = "TestOne",
      })
    )
    lib.files.write(json_path, vim.json.encode(full_gtest_report))

    local notifications = ui_mock.NotificationsMock:new()
    local results = make_neotest_results()
    notifications:revert()

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
    notifications:assert_notified("TestOne.Unparsed", vim.log.levels.WARN)
    notifications:assert_no_other_notifications()
  end)
end)
