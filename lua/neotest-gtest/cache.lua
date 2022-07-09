local utils = require("neotest-gtest.utils")
local async = require("neotest.async")
local Path = require("plenary.path")
local scandir = require("plenary.scandir")
local permissions = require("neotest-gtest.permissions")

local stddata = vim.fn.stdpath("data")
local runs_dir = Path:new(stddata .. "/neotest-gtest/runs")
local IS_WINDOWS = vim.fn.has("win32") == 1
local cache_mode = permissions("rw-r--r--")
local user_name = vim.env.USER

local Cache = {}
local _loaded_caches = {}

-- can't use async.uv.something because the rest of the handler is called in the callback
local function read_sync(file_path)
    local file_fd = assert(vim.loop.fs_open(file_path, "r", 438))
    local stat = assert(vim.loop.fs_fstat(file_fd))
    local data = assert(vim.loop.fs_read(file_fd, stat.size, 0))
    assert(vim.loop.fs_close(file_fd))
    return data
end

local cache_path = stddata .. "/neotest-gtest"

function Cache:cache_for(path)
    local encoded_path = utils.encode_path(path)
    if _loaded_caches[encoded_path] == nil then
        local full_path = string.format("%s/%s.json", cache_path, encoded_path)
        _loaded_caches[encoded_path] = Cache:new(full_path)
    end
    return _loaded_caches[encoded_path]
end

function Cache:new(path)
    local obj = {_path = path, _data = vim.empty_dict()}
    setmetatable(obj, {__index = Cache})

    local exists, _ = utils.fexists(path)
    if not exists then
        obj:flush() -- create the file
    else
        local json = read_sync(path)
        obj._data = json == "" and {} or vim.json.decode(json)
    end

    return obj
end

function Cache:data() return self._data end
function Cache:path() return self._path end

function Cache:flush()
    local as_json = vim.json.encode(self._data)
    if as_json == nil then return end
    local file_fd = assert(vim.loop.fs_open(self._path, "w", cache_mode))
    local bytes = assert(vim.loop.fs_write(file_fd, as_json, 0))
    assert(bytes == #as_json, bytes)
    assert(vim.loop.fs_close(file_fd))
end

local function symlink(path, new_path)
    if not IS_WINDOWS then vim.loop.fs_symlink(path, new_path) end
    -- otherwise just don't bother
end

function Cache:new_results_dir(opts)
    opts = vim.tbl_extend("keep", opts or {}, {history_size = 3})
    local parent_path = Path:new(runs_dir,
                                 string.format("googletest-of-%s", user_name))
    parent_path:mkdir({exist_ok = true})

    local existing_paths = {}
    for _, dir in ipairs(scandir.scan_dir(parent_path.filename,
                                          {depth = 1, only_dirs = true})) do
        if dir:match("%/neotest%-gtest%-run%-%d+$") then
            existing_paths[#existing_paths + 1] = dir
        end
    end

    -- sort newest -> oldest, only leave history_size - 1 files left
    local path2nr = function(p) return tonumber(p:match([[%d+$]])) end
    table.sort(existing_paths, function(l, r) return path2nr(l) > path2nr(r) end)
    for i = opts.history_size, #existing_paths do
        -- making sure we don't remove something important
        assert(existing_paths[i]:match(
            "%/googletest%-of.*%/neotest%-gtest%-run%-%d+$"))
        Path:new(existing_paths[i]):rm({recusrive = true})
    end

    local new_nr
    if #existing_paths == 0 then
        new_nr = 1
    else
        new_nr = path2nr(existing_paths[1]) + 1
    end
    local new_path = Path:new(parent_path,
                              ("neotest-gtest-run-%d"):format(new_nr))
    new_path:mkdir({exist_ok = false})
    symlink(new_path.filename,
            Path:new(parent_path, "neotest-gtest-latest").filename)
    return new_path.filename
end

return Cache
