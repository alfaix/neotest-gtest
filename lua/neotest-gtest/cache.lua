local utils = require("neotest-gtest.utils")
local Path = require("plenary.path")
local scandir = require("plenary.scandir")

local stddata = vim.fn.stdpath("data")
local runs_dir = Path:new(stddata .. "/neotest-gtest/runs")
local cache_path = stddata .. "/neotest-gtest"
local IS_WINDOWS = vim.fn.has("win32") == 1
local cache_mode = utils.permissions("rw-------")
local cache_mode_dir = utils.permissions("rwx------")
local user_name = vim.env.USER

Path:new(cache_path):mkdir({exist_ok=true, mode = cache_mode_dir})
Path:new(runs_dir):mkdir({exist_ok=true, mode = cache_mode_dir})

local Cache = {}
local _loaded_caches = {}

-- I think this might've been true for the old autocmd flush stuff, but no longer true.
-- TODO: move to async stuff if it can be used
-- can't use async.uv.something because the rest of the handler is called in the callback
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
    local full_path = string.format("%s/%s.json", cache_path, encoded_path)
    _loaded_caches[encoded_path] = Cache:new(full_path)
    return _loaded_caches[encoded_path], true
  end
  return _loaded_caches[encoded_path], false
end

function Cache:new(path)
  local obj = { _path = path, _data = { runners = vim.empty_dict() }, _dirty = false }
  setmetatable(obj, { __index = Cache })

  local exists, _ = utils.fexists(path)
  if not exists then
    obj:flush(true) -- create the file
  else
    local json = read_sync(path)
    obj._data = json == "" and {} or vim.json.decode(json)
    if obj._data.runners == nil then
      obj._data.runners = vim.empty_dict()
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

function Cache:list_runners()
  return self._data.runners
end

function Cache:update(key, value)
  local old_data = self._data.runners[key]
  if not json_eq(old_data, value) then
    self._data.runners[key] = value
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

local function symlink(path, new_path)
  if not IS_WINDOWS then
    vim.loop.fs_symlink(path, new_path)
  end
  -- otherwise just don't bother: only used for user's convenience
end

function Cache:new_results_dir(opts)
  opts = vim.tbl_extend("keep", opts or {}, { history_size = 3 })
  local parent_path = Path:new(runs_dir, string.format("googletest-of-%s", user_name))
  parent_path:mkdir({ exist_ok = true })

  local existing_paths = {}
  for _, dir in ipairs(scandir.scan_dir(parent_path.filename, { depth = 1, only_dirs = true })) do
    if dir:match("%/neotest%-gtest%-run%-%d+$") then
      existing_paths[#existing_paths + 1] = dir
    end
  end

  -- sort newest -> oldest, only leave history_size - 1 files left
  local path2nr = function(p)
    return tonumber(p:match([[%d+$]]))
  end
  table.sort(existing_paths, function(l, r)
    return path2nr(l) > path2nr(r)
  end)
  for i = opts.history_size, #existing_paths do
    local path = existing_paths[i]
    -- making sure we don't remove something important
    assert(path:match("%/googletest%-of.*%/neotest%-gtest%-run%-%d+$"))
    Path:new(path):rm({ recusrive = true })
  end

  local new_nr
  if #existing_paths == 0 then
    new_nr = 1
  else
    new_nr = path2nr(existing_paths[1]) + 1
  end
  local new_path = Path:new(parent_path, ("neotest-gtest-run-%d"):format(new_nr))
  new_path:mkdir({ exist_ok = false })
  symlink(new_path.filename, Path:new(parent_path, "neotest-gtest-latest").filename)
  return new_path.filename
end

return Cache
