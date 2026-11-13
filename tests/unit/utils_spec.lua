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

describe("absolute_path", function()
  it("keeps an absolute path unchanged", function()
    assert.equals("/opt/build/tests", utils.absolute_path("/opt/build/tests", "/home/project"))
  end)

  it("resolves a relative path against the base directory", function()
    assert.equals("/home/project/build/tests", utils.absolute_path("build/tests", "/home/project"))
  end)
end)

describe("notify_once", function()
  local original_notify
  local sent

  before_each(function()
    sent = {}
    original_notify = utils.schedule_notify
    utils.schedule_notify = function(msg)
      sent[#sent + 1] = msg
    end
  end)

  after_each(function()
    utils.schedule_notify = original_notify
  end)

  it("sends a repeated message for the same key only once", function()
    utils.notify_once("dedupe-repeat", "same", vim.log.levels.WARN)
    utils.notify_once("dedupe-repeat", "same", vim.log.levels.WARN)

    assert.same({ "same" }, sent)
  end)

  it("sends again after the key is cleared", function()
    utils.notify_once("dedupe-clear", "again", vim.log.levels.WARN)
    utils.notify_clear("dedupe-clear")
    utils.notify_once("dedupe-clear", "again", vim.log.levels.WARN)

    assert.same({ "again", "again" }, sent)
  end)

  it("sends a changed message for the same key", function()
    utils.notify_once("dedupe-change", "first", vim.log.levels.WARN)
    utils.notify_once("dedupe-change", "second", vim.log.levels.WARN)

    assert.same({ "first", "second" }, sent)
  end)
end)

describe("summarize_list", function()
  it("lists short lists in full", function()
    assert.equals("a, b", utils.summarize_list({ "a", "b" }))
  end)

  it("shortens long lists and counts the rest", function()
    assert.equals("a, b, c and 2 more", utils.summarize_list({ "a", "b", "c", "d", "e" }))
  end)
end)

describe("new_results_dir", function()
  it("removes old results folders that still contain files", function()
    nio.scheduler()

    local first = utils.new_results_dir({ history_size = 1 })
    lib.files.write(first .. "/test_result_0.json", "{}")

    local second = utils.new_results_dir({ history_size = 1 })

    assert.is_nil(vim.uv.fs_stat(first))
    assert.is_not_nil(vim.uv.fs_stat(second))

    nio.scheduler()
    vim.fn.delete(second, "rf")
  end)
end)
