local assert = require("luassert")
local async = require("plenary.async")
local utils = require("neotest-gtest.utils")

local a = async.tests

local Cache = require("neotest-gtest.cache")

describe("cache library", function()
  it("Cache is created and deleted", function()
    local tmppath = vim.fn.tempname()
    local cache = Cache:new(tmppath)
    assert.is_true(utils.fexists(tmppath))
    assert.are.equal(tmppath, cache:path())
    cache:drop()
    assert.is_false(utils.fexists(tmppath))
  end)

  it("Cache preserves information", function()
    local tmppath = vim.fn.tempname()
    local cache = Cache:new(tmppath)
    cache:update("key", { value = "foo" })
    cache:flush()
    local cache2 = Cache:new(tmppath)
    assert.are.equal("foo", cache2:list_runners().key.value)
  end)

  -- flushes the Cache with dirty and clean data, then compares mtime after each flush
  it("Cache flushes only when dirty", function()
    local tmppath = vim.fn.tempname()
    local cache = Cache:new(tmppath)

    cache:update("key", { value = "foo" })
    assert.is_true(cache:is_dirty())
    cache:flush(false, true)
    local mtime1 = utils.getmtime(tmppath)
    vim.wait(10)

    cache:update("key", { value = "bar" })
    assert.is_true(cache:is_dirty())
    cache:flush(false, true)
    local mtime2 = utils.getmtime(tmppath)
    vim.wait(10)

    cache:update("key", { value = "bar" })
    assert.is_false(cache:is_dirty())
    cache:flush(false, true)
    local mtime3 = utils.getmtime(tmppath)

    assert.is_true(utils.mtime_lt(mtime1, mtime2))
    assert.is_true(utils.mtime_eq(mtime2, mtime3))
  end)

  it("cache_for does not create redundant caches", function()
    local cache, new = Cache:cache_for("/tmppath")
    -- NB: path is normalized
    local cache2, new2 = Cache:cache_for("/tmppath/")
    assert.is_true(new)
    assert.is_false(new2)
    assert.are.equal(cache, cache2)

    cache:drop()
  end)
  it("different caches do not conflict with each other", function()
    local cache, _ = Cache:cache_for("/tmppath")
    -- NB: path is normalized
    local cache2, _ = Cache:cache_for("/tmppath2")
    cache:update("key", { value = 1 })
    cache:flush()
    cache2:update("key", { value = 2 })
    cache2:flush()

    local cachecopy = Cache:new(cache:path())
    local cachecopy2 = Cache:new(cache2:path())
    assert.is_true(cachecopy:list_runners().key.value == 1)
    assert.is_true(cachecopy2:list_runners().key.value == 2)

    cache:drop()
    cache2:drop()
  end)
end)
