local assert = require("luassert")
local parse_module = require("neotest-gtest.parse")
local lib = require("neotest.lib")
local it = require("nio").tests.it
local tree_utils = require("tests.utils.tree")

local function assert_parses_as(file_content, spec)
  local fpath = assert(vim.fn.tempname()) .. ".cpp"
  lib.files.write(fpath, file_content)
  local tree = parse_module.parse_positions(fpath)
  spec.path = fpath
  tree_utils.assert_tree_meets_spec(tree, spec)
end

describe("config library", function()
  after_each(function() end)

  it("correctly parses simple test", function()
    assert_parses_as(
      [[
      TEST(TestFoo, Bar) {
        doFoo();
      }
      ]],
      {
        {
          name = "TestFoo",
          line_range = { 0, 2 },
          children = {
            {
              name = "Bar",
              line_range = { 0, 2 },
              kind = "TEST",
            },
          },
        },
      }
    )
  end)

  it("correctly parses comment after last parameter", function()
    assert_parses_as(
      [[
      TEST(TestFoo, Bar /* aha! */) {
        doFoo();
      }
      ]],
      {
        {
          name = "TestFoo",
          line_range = { 0, 2 },
        },
      }
    )
  end)

  it("correctly parses comment before first parameter", function()
    assert_parses_as(
      [[
      TEST( // aha!
      TestFoo, Bar) {
        doFoo();
      }
      ]],
      {
        {
          name = "TestFoo",
          line_range = { 0, 3 },
        },
      }
    )
  end)
  it("correctly parses comment between parameters", function()
    assert_parses_as(
      [[
      TEST(TestFoo, // aha!
      Bar) {
        doFoo();
      }
      ]],
      {
        {
          name = "TestFoo",
          line_range = { 0, 3 },
        },
      }
    )
  end)

  it("correctly separates two namespaces", function()
    assert_parses_as(
      [[
      TEST(TestFoo, Bar) {
        doFoo();
      }
      TEST(TestBar, Baz) {
        doFoo();
      }
      ]],
      {
        {
          name = "TestFoo",
          line_range = { 0, 2 },
        },
        {
          name = "TestBar",
          line_range = { 3, 5 },
        },
      }
    )
  end)

  it("correctly separates two tests in the same namespace", function()
    assert_parses_as(
      [[
      TEST(TestFoo, Bar) {
        doFoo();
      }
      TEST(TestFoo, Baz) {
        doFoo();
      }
      ]],
      {
        {
          name = "TestFoo",
          line_range = { 0, 5 },
          children = {
            { name = "Bar", line_range = { 0, 2 } },
            { name = "Baz", line_range = { 3, 5 } },
          },
        },
      }
    )
  end)

  it("correctly parses TEST_F", function()
    assert_parses_as(
      [[
      TEST_F(TestFixture, Foo) {
        doFoo();
      }
      ]],
      {
        {
          name = "TestFixture",
          children = {
            { name = "Foo", line_range = { 0, 2 }, kind = "TEST_F" },
          },
        },
      }
    )
  end)

  it("correctly parses interrupted namespace", function()
    assert_parses_as(
      [[
      TEST(TestFoo, Foo1) {
        doFoo();
      }

      void stuff() {
        // intercepted!
      }

      TEST(TestFoo, Foo2) {
        doFoo();
      }
      ]],
      {
        {
          name = "TestFoo",
          line_range = { 0, 10 },
          children = {
            { name = "Foo1", line_range = { 0, 2 } },
            { name = "Foo2", line_range = { 8, 10 } },
          },
        },
      }
    )
  end)
end)
