local nio = require("nio")
local assert = require("luassert")
local utils = require("neotest-gtest.utils")
local it = require("nio.tests").it

local Storage = require("neotest-gtest.storage")

describe("storage library", function()
  local _storages = {}

  local function new_storage(path)
    local storage = Storage:new(path)
    assert.are.equal(path, storage:path())
    _storages[#_storages + 1] = storage
    return storage
  end

  local function storage_for(path)
    local storage, new = Storage:for_directory(path)
    _storages[#_storages + 1] = storage
    return storage, new
  end

  ---Creates a temporary storage
  ---@return neotest-gtest.Storage
  local function make_tmp_storage()
    local tmppath = assert(nio.fn.tempname())
    return new_storage(tmppath)
  end

  it("Storage is created", function()
    local storage = make_tmp_storage()
    assert.is_true(utils.fexists(storage:path()))
  end)

  it("Storage is deleted", function()
    local storage = make_tmp_storage()
    storage:data()["k"] = "v"
    storage:drop()
    assert.is_false(utils.fexists(storage:path()))
    assert.is_nil(storage:data()["k"])
  end)

  it("Storage preserves information", function()
    local storage = make_tmp_storage()
    storage:data()["key"] = { value = "foo" }
    storage:flush()
    local storage2 = Storage:new(storage:path())
    assert.are.equal("foo", storage2:data().key.value)
  end)

  it("storage_for normalizes the path", function()
    local storage, new = storage_for("/tmppath1")
    local storage2, new2 = storage_for("/tmppath1/")
    assert.is_true(new)
    assert.is_false(new2)
    assert.are.equal(storage, storage2)
  end)

  it("different storages do not conflict with each other", function()
    local storage, _ = make_tmp_storage()
    local storage2, _ = make_tmp_storage()

    storage:data()["key"] = { value = 1 }
    storage:flush()
    storage2:data()["key"] = { value = 2 }
    storage2:flush()

    local storagecopy = Storage:new(storage:path())
    local storagecopy2 = Storage:new(storage2:path())
    assert.are.same({ value = 1 }, storagecopy:data().key)
    assert.are.same({ value = 2 }, storagecopy2:data().key)
  end)

  it("node2executable is created automatically", function()
    local storage, _ = make_tmp_storage()
    assert.is_not_nil(storage:node2executable())
  end)
end)
