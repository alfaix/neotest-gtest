local assert = require("luassert")
local utils = require("neotest-gtest.utils")

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
    local tmppath = assert(vim.fn.tempname())
    return new_storage(tmppath)
  end

  after_each(function()
    for _, storage in ipairs(_storages) do
      storage:drop()
    end
  end)

  it("Storage is created and deleted", function()
    local storage = make_tmp_storage()
    assert.is_true(utils.fexists(storage:path()))
  end)

  it("Storage is deleted", function()
    local storage = make_tmp_storage()
    storage:drop()
    assert.is_false(utils.fexists(storage:path()))
  end)

  it("Storage preserves information", function()
    local storage = make_tmp_storage()
    storage:data()["key"] = { value = "foo" }
    storage:flush(true)
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

  it("old-style node2exec storage is read correctly", function()
    local storage, _ = make_tmp_storage()
    storage:data()["node2exec"] = { value = 1 }
    storage:flush()
    local storage2 = new_storage(storage:path())
    assert.are.equal(storage2:data().value, 1)
    assert.is_nil(storage2:data().node2exec)
  end)
end)
