local M = {}
-- modeled after (copypasted with minimal changes from) neotest/lib/treesitter/init.lua

local nio = require("nio")
local files = require("neotest.lib").files
local types = require("neotest.types")

local Tree = types.Tree
local injections_text = nil

---Extracts test positions from a source using the given query
---@param query vim.treesitter.Query The query to use
---@param source string The text of the source file.
---@param root vim.treesitter.LanguageTree The root of the tree
---@return table
---@return table
local function extract_captures(
  query, --@as table
  source,
  root
)
  -- Namespace definition doesn't really exist as namespace is a made up
  -- construct in GTest used only to group tests together. We set its range
  -- from start of first test to end of last test.
  -- Technically a namespace can be spread across multiple files, but that's
  -- not my problem.

  -- TODO support TEST_P properly with instantiation
  local namespaces = {}
  local tests = {}
  pcall(vim.tbl_add_reverse_lookup, query.captures)
  local gettext = function(match, capture_name)
    return vim.treesitter.get_node_text(match[query.captures[capture_name]], source)
  end

  for _, match in query:iter_matches(root, source) do
    local namespace_name = gettext(match, "namespace.name")
    local test_kind = gettext(match, "test.kind")
    local test_name = gettext(match, "test.name")
    local test_definition = match[query.captures["test.definition"]]

    tests[#tests + 1] = {
      name = test_name,
      kind = test_kind,
      namespace = namespace_name,
      range = { test_definition:range() },
    }

    if namespaces[namespace_name] == nil then
      namespaces[namespace_name] = { test_definition:range() }
    else
      local namespace = namespaces[namespace_name]
      local rowstart, colstart, rowend, colend = test_definition:range()
      if rowstart <= namespace[1] then
        namespace[1] = rowstart
        namespace[2] = math.min(colstart, namespace[2])
      end
      if rowend >= namespace[3] then
        namespace[3] = rowend
        namespace[4] = math.max(colend, namespace[4])
      end
    end
  end
  return namespaces, tests
end

-- TODO support TEST_P and use the index in the name (0/1/2/3)
---Create a unique id for a position by concatenating its name with names of its
---parents.
---@param position neotest.Position The position to return an ID for
---@param parents neotest.Position[] Parent positions for the position
local function position_id(position, parents)
  parents = vim.tbl_map(function(pos)
    return pos.name
  end, parents)
  local elements = vim.tbl_flatten({ position.path, parents, position.name })
  return table.concat(elements, "::")
end

-- level is {parent, children...}
-- Each child is in turn also a level
-- Thus, {a, {b, {c}}, {d}, {e, {f}, {g}}} represents a(b(c))(d)(e(f,g))
-- We only have three levels: file, namespace, test
-- We can consider making TEST_P into a nested namespace but that's probably a
-- bad idea. I do not understand the implcations yet.

---Builds a tree from a list of namespaces and tests extracted from
---the file represented by `fileobj`.
---@param fileobj neotest.Position The file to build the tree for
---@param tests any
---@return table
local function build_tree(fileobj, namespaces, tests)
  local tree = { fileobj }
  local namespace2idx = {}
  for name, range in pairs(namespaces) do
    local namespace = {
      type = "namespace",
      path = fileobj.path,
      name = name,
      range = range,
    }
    namespace.id = position_id(namespace, {})
    tree[#tree + 1] = { namespace }
    namespace2idx[name] = #tree
  end

  for _, test in ipairs(tests) do
    local namespace = tree[namespace2idx[test.namespace]]
    local testobj = {
      type = "test",
      path = fileobj.path,
      name = test.name,
      range = test.range,
      extra = { kind = test.kind },
    }
    testobj.id = position_id(testobj, { namespace[1] })
    namespace[#namespace + 1] = testobj
  end
  return tree
end

local function collect_tests(file_path, query, source, root)
  local path_elems = vim.split(file_path, files.sep, { plain = true })
  local fileobj = {
    id = file_path,
    type = "file",
    path = file_path,
    name = path_elems[#path_elems],
    range = { root:range() },
  }
  local namespaces, tests = extract_captures(query, source, root)
  return build_tree(fileobj, namespaces, tests)
end

function M.parse_positions_from_string(file_path, query, content)
  local ft = files.detect_filetype(file_path)
  local lang = require("nvim-treesitter.parsers").ft_to_lang(ft)
  nio.scheduler()
  local parser = vim.treesitter.get_string_parser(content, lang, nil)
  -- Workaround for https://github.com/neovim/neovim/issues/21275
  -- See https://github.com/nvim-treesitter/nvim-treesitter/issues/4221 for more details
  if injections_text == nil then
    -- TODO can there be more than one?...
    local injection_file = vim.treesitter.query.get_files('cpp', 'injections')[1]
    injections_text = files.read(injection_file)
  end
  vim.treesitter.query.set('cpp', 'injections', '')
  local root = parser:parse()[1]:root()
  vim.treesitter.query.set('cpp', 'injections', injections_text)
  local tests_tree = collect_tests(file_path, query, content, root)
  local tree = Tree.from_list(tests_tree, function(pos)
    return pos.id
  end)
  return tree
end

function M.parse_positions(file_path, query)
  nio.sleep(10)
  local content = files.read(file_path)
  return M.parse_positions_from_string(file_path, query, content)
end

return M
