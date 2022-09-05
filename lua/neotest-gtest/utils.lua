local Path = require("plenary.path")
local M = {}

M.test_extensions = {
  ["cpp"] = true,
  ["cc"] = true,
  ["cxx"] = true,
  ["c++"] = true,
}

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

return M
