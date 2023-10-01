local utils = require("neotest-gtest.utils")
local Path = require("plenary.path")

local cache_mode = utils.permissions("rw-------")

---@class neotest-gtest.Cache
---@field private _data any
---@field private _path string
local Cache = {}
local _loaded_caches = {}

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

function Cache:cache_for(path)
  local encoded_path = utils.encode_path(path)
  if _loaded_caches[encoded_path] == nil then
    local full_path = string.format("%s/%s.json", utils.cache_dir, encoded_path)
    _loaded_caches[encoded_path] = Cache:new(full_path)
    return _loaded_caches[encoded_path], true
  end
  return _loaded_caches[encoded_path], false
end

function Cache:new(path)
  local obj = { _path = path, _data = { node2exec = vim.empty_dict() }, _dirty = false }
  setmetatable(obj, { __index = Cache })

  local exists, _ = utils.fexists(path)
  if not exists then
    obj:flush(true) -- create the file
  else
    local json = read_sync(path)
    obj._data = json == "" and {} or vim.json.decode(json)
    if obj._data.node2exec == nil then
      obj._data.node2exec = vim.empty_dict()
    end
  end

  return obj
end

local function json_eq(lhs, rhs)
  if type(lhs) ~= type(rhs) then
    return false
  end

  if type(lhs) == "table" then
    local lhs_keys = vim.tbl_keys(lhs)
    local rhs_keys = vim.tbl_keys(rhs)
    if #lhs_keys ~= #rhs_keys then
      return false
    end
    for key, value in pairs(lhs) do
      if not json_eq(value, rhs[key]) then
        return false
      end
    end
    return true
  end

  return lhs == rhs
end

function Cache:data()
  return self._data
end

function Cache:update(key, value)
  local old_data = self._data.node2exec[key]
  if not json_eq(old_data, value) then
    self._data.node2exec[key] = value
    self._dirty = true
  end
end

function Cache:path()
  return self._path
end

function Cache:is_dirty()
  return self._dirty
end

---Flushes the cache to disk.
---@param force boolean if true, forces the cache to be flushed even if it's not dirty
function Cache:flush(force, sync)
  if not self._dirty and not force then
    return
  end
  local as_json = vim.json.encode(self._data)
  if as_json == nil then
    return
  end
  local file_fd = assert(vim.loop.fs_open(self._path, "w", cache_mode))
  local nbytes = assert(vim.loop.fs_write(file_fd, as_json, 0))
  assert(nbytes == #as_json, nbytes)
  if sync then
    assert(vim.loop.fs_fsync(file_fd))
  end
  assert(vim.loop.fs_close(file_fd))
  self._dirty = false
end

function Cache:drop()
  return vim.loop.fs_unlink(self._path)
end

return Cache
