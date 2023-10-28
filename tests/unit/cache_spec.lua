local assert = require("luassert")
local utils = require("neotest-gtest.utils")

local Cache = require("neotest-gtest.cache")

---Creates a temporary cache
---@return neotest-gtest.Cache
local function make_tmp_cache()
  local tmppath = assert(vim.fn.tempname())
  local cache = Cache:new(tmppath)
  assert.are.equal(tmppath, cache:path())
  return cache
end

local function write_and_flush(cache, data)
  cache:update("key", data)
  cache:flush(false, true)
end

describe("cache library", function()
  it("Cache is created and deleted", function()
    local cache = make_tmp_cache()
    assert.is_true(utils.fexists(cache:path()))
  end)

  it("Cache is deleted", function()
    local cache = make_tmp_cache()
    cache:drop()
    assert.is_false(utils.fexists(cache:path()))
  end)

  it("Cache preserves information", function()
    local cache = make_tmp_cache()
    cache:update("key", { value = "foo" })
    cache:flush(false, true)
    local cache2 = Cache:new(cache:path())
    assert.are.equal("foo", cache2:data().node2exec.key.value)
  end)

  it("Cache flushes when dirty", function()
    local cache = make_tmp_cache()

    write_and_flush(cache, { value = "foo" })
    local mtime1 = utils.getmtime(cache:path())
    vim.wait(10)

    write_and_flush(cache, { value = "bar" })
    local mtime2 = utils.getmtime(cache:path())

    assert.is_true(utils.mtime_lt(mtime1, mtime2))
  end)

  it("Cache does not flush when not dirty", function()
    local cache = make_tmp_cache()

    write_and_flush(cache, { value = "bar" })
    local mtime1 = utils.getmtime(cache:path())
    vim.wait(10)

    write_and_flush(cache, { value = "bar" })
    local mtime2 = utils.getmtime(cache:path())

    assert.is_true(utils.mtime_eq(mtime1, mtime2))
  end)

  it("cache_for normalizes the path", function()
    local cache, new = Cache:cache_for("/tmppath")
    local cache2, new2 = Cache:cache_for("/tmppath/")
    assert.is_true(new)
    assert.is_false(new2)
    assert.are.equal(cache, cache2)

    cache:drop()
  end)

  it("different caches do not conflict with each other", function()
    local cache, _ = Cache:cache_for("/tmppath3")
    local cache2, _ = Cache:cache_for("/tmppath4")

    cache:update("key", { value = 1 })
    cache:flush()
    cache2:update("key", { value = 2 })
    cache2:flush()

    local cachecopy = Cache:new(cache:path())
    local cachecopy2 = Cache:new(cache2:path())
    assert.are.same({ value = 1 }, cachecopy:data().node2exec.key)
    assert.are.same({ value = 2 }, cachecopy2:data().node2exec.key)

    cache:drop()
    cache2:drop()
  end)
end)
