local scandir = require("plenary.scandir")
local Path = require("plenary.path")
local M = {}

local user_name = vim.env.USER
local IS_WINDOWS = vim.fn.has("win32") == 1
local stddata = vim.fn.stdpath("data")
local runs_dir = Path:new(stddata .. "/neotest-gtest/runs")
local cache_dir = stddata .. "/neotest-gtest"
M.cache_dir = cache_dir

local permissions_table = {
  -- user r/w/x
  tonumber("00400", 8),
  tonumber("00200", 8),
  tonumber("00100", 8),
  -- group r/w/x
  tonumber("00040", 8),
  tonumber("00020", 8),
  tonumber("00010", 8),
  -- others r/w/x
  tonumber("00004", 8),
  tonumber("00002", 8),
  tonumber("00001", 8),
}

---Creates a permissions mode number from a string.
---@param str string in the format "rwxrwxrwx", where any letter can be "-" to indicate no permission. Note that the letters themselves are ignored, only order matters.
---@return integer the permissions mode number
function M.permissions(str)
  assert(#str == #permissions_table, "mode string mut have 9 chars, e.g. rw-rwxrwx")
  local mode = 0
  for i = 1, #str do
    if str:sub(i, i) ~= "-" then
      mode = bit.bor(mode, permissions_table[i])
    end
  end
  return mode
end

local cache_mode_dir = M.permissions("rwx------")
Path:new(cache_dir):mkdir({ exist_ok = true, mode = cache_mode_dir })
Path:new(runs_dir):mkdir({ exist_ok = true, mode = cache_mode_dir })

M.test_extensions = {
  ["cpp"] = true,
  ["cppm"] = true,
  ["cc"] = true,
  ["cxx"] = true,
  ["c++"] = true,
}

---@class neotest-gtest.mtime
---@field sec number Unix timestamp of file's mtime
---@field nsec number Nanosecond offset of file's mtime from the star of the second

---Compares mtimes `lhs` and `rhs`, returning true if `lhs` is smaller.
---@param lhs neotest-gtest.mtime First mtime to compare
---@param rhs neotest-gtest.mtime Second mtime to compare
---@return boolean Whether `lhs` is smaller than `rhs`
function M.mtime_lt(lhs, rhs)
  if lhs.sec < rhs.sec then
    return true
  end
  if lhs.sec == rhs.sec then
    return lhs.nsec < rhs.nsec
  end
  return false
end

---Compares mtimes `lhs` and `rhs`, returning true if they are equal
---@param lhs neotest-gtest.mtime First mtime to compare
---@param rhs neotest-gtest.mtime Second mtime to compare
---@return boolean Whether `lhs` is equal to `rhs`
function M.mtime_eq(lhs, rhs)
  return lhs.sec == rhs.sec and lhs.nsec == rhs.nsec
end

---Returns mtime table for the file at `path`
---@param path string path to the file to inspect
---@return neotest-gtest.mtime mtime table for the file at `path`
---@return string error message if an error occurred
function M.getmtime(path)
  local stat, e = vim.loop.fs_stat(path)
  if e then
    return nil, e
  end
  return stat.mtime, nil
end

---Check if a file at path `path` exists and is a regular file.
---@param path string The path to check
---@return boolean whether the path leads to a regular file
---@return string|nil human-readable error message if the path is not a regular file
function M.fexists(path)
  local stat, e = vim.loop.fs_stat(path)
  if e then
    return false, e
  end
  if stat.type == "file" then
    return true, nil
  end
  -- TODO check it's executable? permissions and shit
  return false, string.format("Expected regular file, found %s instead", stat.type)
end

---Analyzes the path to determine whether the file is a C++ test file or not.
---
---Simply checks if the file fits either "test_*.ext" or "*_test.ext" pattern,
---where ext is one of the extensions in `M.test_extensions`.
---
---@param file_path string the path to analyze
---@return boolean true if `path` is a test file, false otherwise.
function M.is_test_file(file_path)
  local elems = vim.split(file_path, Path.path.sep, { plain = true })
  local filename = elems[#elems]
  if filename == "" then -- directory
    return false
  end
  local extsplit = vim.split(filename, ".", { plain = true })
  local extension = extsplit[#extsplit]
  local fname_last_part = extsplit[#extsplit - 1]
  local result = M.test_extensions[extension]
      and (vim.startswith(filename, "test_") or vim.endswith(fname_last_part, "_test"))
    or false
  return result
end

---Normalizes the path. This ensures that all paths pointing to the same file
---(excluding symlinks) are the same.
---
---There is no universal way to handle symlinks for all project layouts, so the
---user will have to configure symlinks by hand as if they are different files.
---
---@param path string the path to normalize
---@return string string the normalized path string
function M.normalize_path(path)
  if path:sub(1, 1) == "~" and (path:sub(2, 2) == Path.path.sep or #path == 1) then
    path = vim.loop.os_getenv("HOME") .. path:sub(2)
  end
  if #path ~= 1 and vim.endswith(path, Path.path.sep) then
    path = path:sub(1, -2)
  end
  return Path:new(path):absolute()
end

---Encodes a path in a way that it can be used as a file name. Guaranteed to
---encode different paths differently.
---@param path string the path to encode. Must be a valid path or the result may
---       not be a valid name
---@return string the encoded path
function M.encode_path(path)
  path = M.normalize_path(path)
  local encoded = path:gsub("%%", "%%1")
  encoded = encoded:gsub("%" .. Path.path.sep, "%%0")
  return encoded
end

---Decodes a path previously encoded by `encode_path`.
---@param encoded_path string the path to decode
---@return string the decoded path
function M.decode_path(encoded_path)
  encoded_path = encoded_path:gsub("%%0", Path.path.sep)
  encoded_path = encoded_path:gsub("%%1", "%%")
  return encoded_path
end

---Returns a list of words parsed from the string `input`. Words are separated
---by spaces, "words" with spaces must be enclosed in single quotes.
---@param inpt string the string to parse
---@return string[]|nil the list of words
---@return string|nil parsing error if any (e.g., unterminated quote)
function M.parse_words(inpt)
  local quoted = false
  local start = 1
  local words = {}
  local i = 1
  while i <= #inpt + 1 do
    local ch
    if i == #inpt + 1 then
      ch = " "
    else
      ch = inpt:sub(i, i)
    end
    if ch == "'" or (ch == " " and not quoted) then
      local word
      word = inpt:sub(start, i - 1)
      if #word ~= 0 and word:find("[^%s]") then
        words[#words + 1] = word
      end
      start = i + 1
      if ch == "'" then
        quoted = not quoted
      end
    end
    i = i + 1
  end
  if quoted then
    return nil, "unterminated quote"
  end
  return words, nil
end

local function symlink(path, new_path)
  if not IS_WINDOWS then
    vim.loop.fs_symlink(path, new_path)
  end
  -- otherwise just don't bother: only used for user's convenience
end

function M.new_results_dir(opts)
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

function M.list_to_set(list)
  local set = {}
  for i = 1, #list do
    set[list[i]] = true
  end
  return set
end

function M.map_list(map_fn, table)
  local i = 0
  return function()
    i = i + 1
    if i <= #table then
      return map_fn(table[i])
    end
  end,
    nil,
    nil
end

function M.collect_iterable(...)
  local list = {}
  for v in ... do
    table.insert(list, v)
  end
  return list
end

return M
