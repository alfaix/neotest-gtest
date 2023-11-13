local assert = require("luassert")
local utils = require("neotest-gtest.utils")

local Cache = require("neotest-gtest.cache")

describe("cache library", function()
  local _caches = {}

  local function new_cache(path)
    local cache = Cache:new(path)
    assert.are.equal(path, cache:path())
    _caches[#_caches + 1] = cache
    return cache
  end

  local function cache_for(path)
    local cache, new = Cache:cache_for(path)
    _caches[#_caches + 1] = cache
    return cache, new
  end

  ---Creates a temporary cache
  ---@return neotest-gtest.Cache
  local function make_tmp_cache()
    local tmppath = assert(vim.fn.tempname())
    return new_cache(tmppath)
  end

  after_each(function()
    for _, cache in ipairs(_caches) do
      cache:drop()
    end
  end)

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
    cache:data()["key"] = { value = "foo" }
    cache:flush(true)
    local cache2 = Cache:new(cache:path())
    assert.are.equal("foo", cache2:data().key.value)
  end)

  it("cache_for normalizes the path", function()
    local cache, new = cache_for("/tmppath1")
    local cache2, new2 = cache_for("/tmppath1/")
    assert.is_true(new)
    assert.is_false(new2)
    assert.are.equal(cache, cache2)
  end)

  it("different caches do not conflict with each other", function()
    local cache, _ = make_tmp_cache()
    local cache2, _ = make_tmp_cache()

    cache:data()["key"] = { value = 1 }
    cache:flush()
    cache2:data()["key"] = { value = 2 }
    cache2:flush()

    local cachecopy = Cache:new(cache:path())
    local cachecopy2 = Cache:new(cache2:path())
    assert.are.same({ value = 1 }, cachecopy:data().key)
    assert.are.same({ value = 2 }, cachecopy2:data().key)
  end)

  it("old-style node2exec cache is read correctly", function()
    local cache, _ = make_tmp_cache()
    cache:data()["node2exec"] = { value = 1 }
    cache:flush()
    local cache2 = new_cache(cache:path())
    assert.are.equal(cache2:data().value, 1)
    assert.is_nil(cache2:data().node2exec)
  end)
end)
