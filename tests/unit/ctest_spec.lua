local assert = require("luassert")
local ctest = require("neotest-gtest.executables.ctest")

local function set(list)
  local s = {}
  for _, v in ipairs(list) do
    s[v] = true
  end
  return s
end

describe("pick_executable", function()
  local A, B = "/build/a_tests", "/build/b_tests"

  it("picks the binary containing most of the file's tests", function()
    local exe2tests = { [A] = set({ "S.t1", "S.t2" }), [B] = set({ "S.t1" }) }
    assert.equals(A, ctest._pick_executable(exe2tests, { "S.t1", "S.t2" }, nil))
  end)

  it("breaks a tie with the compile target", function()
    local exe2tests = { [A] = set({ "S.t1" }), [B] = set({ "S.t1" }) }
    assert.equals(B, ctest._pick_executable(exe2tests, { "S.t1" }, "b_tests"))
  end)

  it("breaks a tie without a target deterministically", function()
    local exe2tests = { [A] = set({ "S.t1" }), [B] = set({ "S.t1" }) }
    assert.equals(A, ctest._pick_executable(exe2tests, { "S.t1" }, nil))
    assert.equals(
      A,
      ctest._pick_executable({ [B] = set({ "S.t1" }), [A] = set({ "S.t1" }) }, { "S.t1" }, nil)
    )
  end)

  it("maps a file without tests to its compile target", function()
    local exe2tests = { [A] = set({ "S.t1" }), [B] = set({ "S.t2" }) }
    assert.equals(A, ctest._pick_executable(exe2tests, {}, "a_tests"))
  end)

  it("leaves a file without tests and without target unmapped", function()
    assert.is_nil(ctest._pick_executable({ [A] = set({ "S.t1" }) }, {}, nil))
  end)

  it("leaves a file whose tests are in no binary unmapped", function()
    assert.is_nil(ctest._pick_executable({ [A] = set({ "S.t1" }) }, { "Other.t" }, "a_tests"))
  end)

  it("matches parameterized instances to their source test", function()
    local exe2tests = {
      [A] = set({ "First/Fixture.Case/0", "First/Fixture.Case/1" }),
      [B] = set({ "Other.Case" }),
    }
    assert.equals(A, ctest._pick_executable(exe2tests, { "Fixture.Case" }, nil))
  end)
end)

describe("parse_ctest_json", function()
  it("keys by executable and gtest filter, dropping non-gtest tests", function()
    local json = vim.json.encode({
      tests = {
        { name = "lint", command = { "/usr/bin/python3", "lint.py" } },
        {
          name = "prefix_S.t1",
          command = { "/build/a_tests", "--gtest_filter=S.t1", "--gtest_also_run_disabled_tests" },
        },
        { name = "S.t2", command = { "/build/a_tests", "--gtest_filter=S.t2" } },
        { name = "S.t1", command = { "/build/b_tests", "--gtest_filter=S.t1" } },
      },
    })
    assert.same({
      ["/build/a_tests"] = { ["S.t1"] = true, ["S.t2"] = true },
      ["/build/b_tests"] = { ["S.t1"] = true },
    }, ctest._parse_ctest_json(json))
  end)

  it("tolerates a test without a command", function()
    assert.same({}, ctest._parse_ctest_json(vim.json.encode({ tests = { { name = "x" } } })))
  end)
end)

describe("parse_compile_db", function()
  it("reads directory and target from a command string", function()
    local db = ctest._parse_compile_db(vim.json.encode({
      {
        directory = "/build/pkg/test",
        file = "/src/pkg/test/foo_test.cpp",
        command = "clang++ -o CMakeFiles/foo_tests.dir/foo_test.cpp.o -c /src/pkg/test/foo_test.cpp",
      },
    }))
    assert.same(
      { directory = "/build/pkg/test", target = "foo_tests" },
      db["/src/pkg/test/foo_test.cpp"]
    )
  end)

  it("reads an arguments array", function()
    local db = ctest._parse_compile_db(vim.json.encode({
      {
        directory = "/build",
        file = "/src/x.cpp",
        arguments = { "clang++", "-o", "CMakeFiles/x.dir/x.cpp.o", "-c", "/src/x.cpp" },
      },
    }))
    assert.equals("x", db["/src/x.cpp"].target)
  end)

  it("has no target when the object path is not CMake-shaped", function()
    local db = ctest._parse_compile_db(vim.json.encode({
      { directory = "/build", file = "/src/x.cpp", command = "cc -o x.o -c /src/x.cpp" },
    }))
    assert.is_nil(db["/src/x.cpp"].target)
  end)
end)
