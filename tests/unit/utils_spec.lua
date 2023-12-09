local nio = require("nio")
local helpers = require("tests.utils.helpers")
local assert = require("luassert")
local utils = require("neotest-gtest.utils")
local config = require("neotest-gtest.config")
local it = nio.tests.it
local lib = require("neotest.lib")

---@source https://stackoverflow.com/questions/6380820/get-containing-path-of-lua-file
local function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end

describe("helper functions", function()
  after_each(function()
    config.reset()
  end)

  describe("path-related helpers", function()
    it("paths pointing to the same file normalize to identical strings", function()
      assert.are.equal(utils.normalize_path("~/foo/bar"), nio.fn.expand("~/foo/bar", nil, nil))
      assert.are.equal(utils.normalize_path("/foo/bar"), "/foo/bar")
      assert.are.equal(utils.normalize_path("/foo/bar"), "/foo/bar")
      assert.are.equal(utils.normalize_path("/foo/bar/"), utils.normalize_path("/foo/bar"))
      assert.are.equal(
        utils.normalize_path("./tests/unit/utils_spec.lua"),
        script_path() .. "utils_spec.lua"
      )
    end)

    it("fexists only returns true on existing regular files", function()
      assert.is_true(utils.fexists(script_path() .. "utils_spec.lua"))
      assert.is_false(utils.fexists("/")) -- files only!
      assert.is_false(utils.fexists("/nowayyouactuallycreatedafilewiththisname"))
    end)

    it("path's encoding is valid and consistent", function()
      local check = function(p)
        local encoded = utils.encode_path(p)
        local decoded = utils.decode_path(encoded)
        assert.are.equal(decoded, p)
        assert.is.Nil(encoded:match("/"))
      end
      check("/foo%/bar%/baz.baz")
      check("/")
    end)
  end)

  it("words are properly separated", function()
    local words, err = utils.parse_words("foo bar baz")
    assert.is.Nil(err)
    assert.are.same(words, { "foo", "bar", "baz" })

    words, err = utils.parse_words("foo 'bar baz'")
    assert.is.Nil(err)
    assert.are.same(words, { "foo", "bar baz" })

    words, err = utils.parse_words("foo 'bar baz")
    assert.is.truthy(err)
    assert.is.Nil(words)
  end)

  it("mtime is read and compared correctly", function()
    local mtime1, err = utils.getmtime(script_path() .. "utils_spec.lua")
    assert.is.Nil(err)

    local tmp = nio.fn.tempname()
    nio.fn.writefile({ "foo" }, tmp, "s")
    local mtime2
    mtime2, err = utils.getmtime(tmp)
    assert.is.Nil(err)
    assert(mtime2)
    assert(mtime1)
    assert.is_true(utils.mtime_lt(mtime1, mtime2))
    assert.is_true(utils.mtime_eq(mtime1, mtime1))
    assert.is_true(utils.mtime_eq(mtime2, mtime2))
  end)

  it("list_to_set converts list correctly", function()
    local list = { "foo", "bar", "baz" }
    local set = utils.list_to_set(list)
    assert.are.same(set, { foo = true, bar = true, baz = true })
  end)

  it("list_to_set converts empty list", function()
    local list = {}
    local set = utils.list_to_set(list)
    assert.are.same(set, {})
  end)

  it("collect_iterable collects empty iterable", function()
    local t = {}
    assert.are.same(utils.collect_iterable(pairs(t)), t)
  end)

  it("collect_iterable collects non-empty iterable", function()
    local t = { 1, 2, 3, 4 }
    assert.are.same(utils.collect_iterable(pairs(t)), t)
  end)

  it("map_list returns empty iterable for empty table", function()
    local list = {}
    local mapped = utils.collect_iterable(utils.map_list(function(x)
      return x
    end, list))
    assert.are.same({}, mapped)
  end)

  it("map_list maps a list correctly", function()
    local list = { 1, 2, 3 }
    local mapped = utils.collect_iterable(utils.map_list(function(x)
      return x + 1
    end, list))
    assert.are.same({ 2, 3, 4 }, mapped)
  end)

  it("copy() creates a shallow copy of the table", function()
    local t1 = { a = 1, b = 2 }
    local t2 = utils.tbl_copy(t1)
    assert.are.same(t1, t2)
    assert.is_false(t1 == t2)
  end)

  it("normalized_root() normalizes user-supplied root", function()
    config.setup({
      root = function(path)
        return "/usr/"
      end,
    })
    assert.are.equal("/usr", utils.normalized_root("anything"))
  end)
end)
