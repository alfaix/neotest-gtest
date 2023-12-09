local assert = require("luassert")
local nio = require("nio")
local lib = require("neotest.lib")
local M = {}

local function find_all_occurences(str, substr)
  local occurences = {}
  local i

  while true do
    i = string.find(str, substr, i, true)
    if i == nil then
      break
    end
    table.insert(occurences, i)
    i = i + 1
  end
  return occurences
end

function M.string_replace(str, substr, replacement)
  local occurences = find_all_occurences(str, substr)
  local correction = 0
  for _, pos in ipairs(occurences) do
    str = str:sub(1, pos - 1 + correction) .. replacement .. str:sub(pos + #substr + correction)
    correction = correction + #replacement - #substr
  end
  return str
end

function M.dedent(str)
  local lines = vim.split(str, "\n", { plain = true })
  local indent = string.find(lines[1], "%S")
  if indent == nil then
    return str
  end
  for i, line in ipairs(lines) do
    lines[i] = line:sub(indent)
  end
  return vim.trim(table.concat(lines, "\n"))
end

---@return string
function M.mktempdir()
  local path = assert(nio.fn.tempname())
  nio.uv.fs_mkdir(path, tonumber("0700", 8))
  return path
end

local function parent_dir(path)
  local sep_index = string.find(path, lib.files.sep, 1, true)
  if sep_index == nil then
    return nil
  end
  return string.sub(path, 1, sep_index - 1)
end

function M.write_file_tree(root, relpath2contents)
  M.mkdir(root)
  local created = { [root] = true }
  for relpath, contents in pairs(relpath2contents) do
    local parent = parent_dir(relpath)
    if parent ~= nil and not created[parent] then
      M.mkdir(parent)
      created[parent] = true
    end
    local abspath = string.format("%s%s%s", root, lib.files.sep, relpath)
    lib.files.write(abspath, contents)
  end
end

function M.mkdir(path, opts)
  opts = opts or { exist_ok = true }
  local err, _ = nio.uv.fs_mkdir(path, tonumber("0700", 8))
  if err ~= nil and not (opts.exist_ok and vim.startswith(err, "EEXIST")) then
    error(err)
  end
end

function M.assert_same_keys(table1, table2)
  return M.assert_same_ignore_order(vim.tbl_keys(table1), vim.tbl_keys(table2))
end

function M.assert_same_ignore_order(list1, list2, comp)
  table.sort(list1, comp)
  table.sort(list2, comp)
  assert.are_same(list1, list2)
end

return M
