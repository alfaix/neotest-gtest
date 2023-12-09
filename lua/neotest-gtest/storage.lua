local nio = require("nio")
local lib = require("neotest.lib")
local utils = require("neotest-gtest.utils")

---@class neotest-gtest.Storage
---@field private _data any
---@field private _path string
local Storage = {}
local _loaded_storages = {}

---Creates a new storage
---@param path string Directory for which the storage shall maintain executables.
---@return neotest-gtest.Storage
---@return boolean is_new True if the storage was loaded from disk, false if returned from memory.
function Storage:for_directory(path)
  local encoded_path = utils.encode_path(path)
  if _loaded_storages[encoded_path] == nil then
    local full_path = string.format("%s/%s.json", utils.storage_dir, encoded_path)
    _loaded_storages[encoded_path] = Storage:new(full_path)
    return _loaded_storages[encoded_path], true
  end
  return _loaded_storages[encoded_path], false
end

---Creates a new storage
---@param path string Path at which the storage data will be stored
---@return neotest-gtest.Storage
function Storage:new(path)
  local obj = { _path = path, _data = vim.empty_dict() }
  setmetatable(obj, { __index = Storage })

  local exists, _ = utils.fexists(path)
  if exists then
    local json = lib.files.read(path)
    obj._data = json == "" and vim.empty_dict() or vim.json.decode(json)
  else
    obj:flush(true) -- create the file
  end

  return obj
end

function Storage:data()
  return self._data
end

function Storage:node2executable()
  if self._data.node2executable == nil then
    self._data.node2executable = vim.empty_dict()
  end
  return self._data.node2executable
end

function Storage:path()
  return self._path
end

---Flushes the in-memory data() to disk.
---@param sync boolean|nil
function Storage:flush(sync)
  local as_json = vim.json.encode(self._data)
  if as_json == nil then
    return
  end
  lib.files.write(self._path, as_json)
end

function Storage:drop()
  self._data = vim.empty_dict()
  return nio.uv.fs_unlink(self._path)
end

return Storage
