local utils = require("neotest-gtest.utils")

local storage_mode = tonumber("600", 8)

---@class neotest-gtest.Storage
---@field private _data any
---@field private _path string
local Storage = {}
local _loaded_storages = {}

-- I think this might've been true for the old autocmd flush stuff, but no longer true.
-- TODO: move to async stuff if it can be used
-- can't use async.uv.something because the rest of the handler is called in the callback
-- @return string contents Contents of the file at `file_path`
local function read_sync(file_path)
  local file_fd = assert(vim.loop.fs_open(file_path, "r", 438))
  local stat = assert(vim.loop.fs_fstat(file_fd))
  local data = assert(vim.loop.fs_read(file_fd, stat.size, 0))
  assert(vim.loop.fs_close(file_fd))
  return data
end

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
  if not exists then
    obj:flush(true) -- create the file
  else
    local json = read_sync(path)
    obj._data = json == "" and vim.empty_dict() or vim.json.decode(json)
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
  local file_fd = assert(vim.loop.fs_open(self._path, "w", storage_mode))
  local nbytes = assert(vim.loop.fs_write(file_fd, as_json, 0))
  assert(nbytes == #as_json, nbytes)
  if sync then
    assert(vim.loop.fs_fsync(file_fd))
  end
  assert(vim.loop.fs_close(file_fd))
end

function Storage:drop()
  return vim.loop.fs_unlink(self._path)
end

return Storage
