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

  it("shows TEST_P as a test position", function()
    assert_parses_as(
      [[
      TEST_P(ParamFixture, Positive) {
        EXPECT_GE(GetParam(), 0);
      }
      ]],
      {
        {
          name = "ParamFixture",
          children = {
            { name = "Positive", line_range = { 0, 2 }, kind = "TEST_P" },
          },
        },
      }
    )
  end)

  it("shows TYPED_TEST as a source position with exact runtime leaves", function()
    local fpath = assert(vim.fn.tempname()) .. ".cpp"
    local source_id = fpath .. "::TypedFixture::Works"
    local runtime_names = { "TypedFixture/Small.Works", "TypedFixture/Large.Works" }

    lib.files.write(
      fpath,
      [[
TYPED_TEST(TypedFixture, Works) {
  EXPECT_TRUE(true);
}
]]
    )

    local tree = parse_module.parse_positions(fpath, {
      [source_id] = runtime_names,
    })
    local source = assert(tree:get_key(source_id))

    assert.equals("TYPED_TEST", source:data().extra.kind)
    assert.equals(2, #source:children())
    for _, name in ipairs(runtime_names) do
      local leaf = assert(tree:get_key(source_id .. "::" .. name))

      assert.equals(name, leaf:data().extra.runtime_name)
      assert.equals("TYPED_TEST", leaf:data().extra.kind)
    end
  end)

  it("shows TYPED_TEST_P with leaves from multiple instantiations", function()
    local fpath = assert(vim.fn.tempname()) .. ".cpp"
    local source_id = fpath .. "::PatternFixture::Works"
    local runtime_names = {
      "First/PatternFixture/0.Works",
      "First/PatternFixture/1.Works",
      "Second/PatternFixture/0.Works",
    }

    lib.files.write(fpath, "TYPED_TEST_P(PatternFixture, Works) {}")

    local tree = parse_module.parse_positions(fpath, {
      [source_id] = runtime_names,
    })
    local source = assert(tree:get_key(source_id))

    assert.equals("TYPED_TEST_P", source:data().extra.kind)
    assert.equals(3, #source:children())

    for _, name in ipairs(runtime_names) do
      local leaf = assert(tree:get_key(source_id .. "::" .. name))

      assert.equals(name, leaf:data().extra.runtime_name)
      assert.equals("TYPED_TEST_P", leaf:data().extra.kind)
    end
  end)

  it("adds exact runtime children beneath their source declarations", function()
    local source = [[
      TEST_P(ParamFixture, Positive) {}
      TEST_P(ParamFixture, Small) {}
    ]]
    local fpath = assert(vim.fn.tempname()) .. ".cpp"

    lib.files.write(fpath, source)

    local tree = parse_module.parse_positions(fpath, {
      [fpath .. "::ParamFixture::Positive"] = {
        "First/ParamFixture.Positive/0",
        "First/ParamFixture.Positive/1",
        "Second/ParamFixture.Positive/0",
      },
      [fpath .. "::ParamFixture::Small"] = {
        "First/ParamFixture.Small/0",
        "Second/ParamFixture.Small/0",
      },
    })

    local positive = assert(tree:get_key(fpath .. "::ParamFixture::Positive"))
    local small = assert(tree:get_key(fpath .. "::ParamFixture::Small"))

    assert.equals(3, #positive:children())
    assert.equals(2, #small:children())

    for _, child in ipairs(positive:children()) do
      local data = child:data()

      assert.equals("test", data.type)
      assert.equals(positive:data().id .. "::" .. data.name, data.id)
      assert.equals(data.name, data.extra.runtime_name)
      assert.equals("TEST_P", data.extra.kind)
    end

    assert.equals(
      positive:data().id,
      lib.positions.nearest(tree, positive:data().range[1]):data().id
    )
  end)

  it("keeps an unconfigured TEST_P source without invented children", function()
    local fpath = assert(vim.fn.tempname()) .. ".cpp"

    lib.files.write(fpath, "TEST_P(ParamFixture, Positive) {}")

    local tree = parse_module.parse_positions(fpath)
    local source = assert(tree:get_key(fpath .. "::ParamFixture::Positive"))

    assert.equals(0, #source:children())
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
