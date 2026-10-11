local M = {}
-- modeled after (copypasted with minimal changes from) neotest/lib/treesitter/init.lua

local config = require("neotest-gtest.config")
local nio = require("nio")
local files = require("neotest.lib").files
local ts_lib = require("neotest.lib").treesitter
local types = require("neotest.types")

local Tree = types.Tree
local injections_text = nil

-- treesitter matches TEST macros as function definitions
-- treesitter cannot possibly know about macros defined in other files, so this
-- is the best we can do. It works pretty well though.
-- under C standard, they are valid definitions with implicit int return type
-- (and with proper compiler flags the CPP code should also compile which should
--  mean that treesitter should continue to parse these as function definitions)
-- Thus, we match all function definitions that meet ALL of the following criteria:
-- * Named TEST/TEST_F/TEST_P/TYPED_TEST/TYPED_TEST_P (#any-of)
-- * Do not declare a return type (!type)
-- * Only have two parameters (. anchors)
-- * Both parameters are unnamed (!declarator)
-- * Both parameters' type is a simple type_identifier, i.e., no references
--   or cv-qualifiers or templates (type: (type_identifier))
-- The first parameter is the test suite, the second one is the test case
-- The name of the "function" is the test kind.
local TREESITTER_GTEST_QUERY = vim.treesitter.query.parse(
  "cpp",
  [[
  ((function_definition
    declarator: (
        function_declarator
          declarator: (identifier) @test.kind
        parameters: (
          parameter_list
            (parameter_declaration type: (type_identifier) !declarator) @namespace.name
            (parameter_declaration type: (type_identifier) !declarator) @test.name
        )
      )
      !type
  )
  (#any-of? @test.kind "TEST" "TEST_F" "TEST_P" "TYPED_TEST" "TYPED_TEST_P"))
  @test.definition
]]
)

local function add_reverse_lookup(tbl)
  local keys = vim.tbl_keys(tbl)
  for _, key in ipairs(keys) do
    tbl[tbl[key]] = key
  end
  return tbl
end

---Extracts test positions from a source using the given query
---@param query vim.treesitter.Query The query to use
---@param source string The text of the source file.
---@param root TSNode The root of the tree
---@return table
---@return table
local function extract_captures(
  query, --@as table
  source,
  root
)
  local namespaces = {}
  local tests = {}
  add_reverse_lookup(query.captures)

  local source_lines = vim.split(source, "\n", { plain = true })
  local gettext = function(match, capture_name)
    local nodes = match[query.captures[capture_name]]
    local node = nodes and nodes[1]
    if node == nil then
      error(vim.inspect({ node, match, query.captures, capture_name }))
    end
    local sr, sc, er, ec = node:range()
    if sr == er then
      return source_lines[sr + 1]:sub(sc + 1, ec)
    end
    local parts = { source_lines[sr + 1]:sub(sc + 1) }
    for i = sr + 2, er do
      parts[#parts + 1] = source_lines[i]
    end
    parts[#parts + 1] = (source_lines[er + 1] or ""):sub(1, ec)
    return table.concat(parts, "\n")
  end

  for _, match in query:iter_matches(root, source) do
    local namespace_name = gettext(match, "namespace.name")
    local test_kind = gettext(match, "test.kind")
    local test_name = gettext(match, "test.name")
    local test_definition = match[query.captures["test.definition"]][1]
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

---Create a unique id for a position by concatenating its name with names of its
---parents.
---@param position neotest.Position The position to return an ID for
---@param parents neotest.Position[] Parent positions for the position
local function position_id(position, parents)
  parents = vim.tbl_map(function(pos)
    return pos.name
  end, parents)
  local elements = vim.iter({ position.path, parents, position.name }):flatten():totable()
  return table.concat(elements, "::")
end

-- level is {parent, children...}
-- Each child is in turn also a level
-- Thus, {a, {b, {c}}, {d}, {e, {f}, {g}}} represents a(b(c))(d)(e(f,g))
-- Generated runtime cases form a fourth level below their source declaration.

local function is_generated_kind(kind)
  return kind == "TEST_P" or kind == "TYPED_TEST" or kind == "TYPED_TEST_P"
end

---Builds a tree from a list of namespaces and tests extracted from
---the file represented by `fileobj`.
---@param fileobj neotest.Position The file to build the tree for
---@param tests any
---@return table
local function build_tree(fileobj, namespaces, tests, runtime_by_source)
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
    local source = testobj
    if is_generated_kind(test.kind) and runtime_by_source and runtime_by_source[testobj.id] then
      source = { testobj }
      for _, runtime_name in ipairs(runtime_by_source[testobj.id]) do
        source[#source + 1] = {
          id = testobj.id .. "::" .. runtime_name,
          type = "test",
          path = fileobj.path,
          name = runtime_name,
          range = test.range,
          extra = { kind = test.kind, runtime_name = runtime_name },
        }
      end
    end
    namespace[#namespace + 1] = source
  end
  return tree
end

local function collect_tests(file_path, source, root, runtime_by_source)
  local path_elems = vim.split(file_path, files.sep, { plain = true })
  local fileobj = {
    id = file_path,
    type = "file",
    path = file_path,
    name = path_elems[#path_elems],
    range = { root:range() },
  }
  local namespaces, tests = extract_captures(TREESITTER_GTEST_QUERY, source, root)
  return build_tree(fileobj, namespaces, tests, runtime_by_source)
end

local function get_file_language(file_path)
  local ft = files.detect_filetype(file_path)
  return vim.treesitter.language.get_lang(ft)
end

local function parser_get_tree(lang_tree)
  -- Workaround for https://github.com/neovim/neovim/issues/21275
  -- See https://github.com/nvim-treesitter/nvim-treesitter/issues/4221 for more details
  if injections_text == nil then
    -- TODO can there be more than one?...
    local injection_file = vim.treesitter.query.get_files("cpp", "injections")[1]
    injections_text = files.read(injection_file)
  end
  vim.treesitter.query.set("cpp", "injections", "")

  local root = ts_lib.fast_parse(lang_tree):root()

  vim.treesitter.query.set("cpp", "injections", injections_text)
  return root
end

local function parse_positions_from_string(file_path, content, runtime_by_source)
  local lang = get_file_language(file_path)
  local lang_tree = vim.treesitter.get_string_parser(content, lang, nil)
  local treesitter_tree = parser_get_tree(lang_tree)
  local tests_tree = collect_tests(file_path, content, treesitter_tree, runtime_by_source)
  local neotest_tree = Tree.from_list(tests_tree, function(pos)
    return pos.id
  end)
  return neotest_tree
end

function M.parse_positions(file_path, runtime_by_source)
  -- throttle: can cause very high CPU load for large projects and freeze
  nio.sleep(config.parsing_throttle_ms)
  local content = files.read(file_path)
  nio.scheduler()
  return parse_positions_from_string(file_path, content, runtime_by_source)
end

return M
