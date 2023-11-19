local MockProject = require("tests.utils.mock_project")
local parse_module = require("neotest-gtest.parse")
local lib = require("neotest.lib")
local assert = require("luassert")

local M = {}

local function id_sorter(lhs, rhs)
  return lhs.id < rhs.id
end

local function data_id_sorter(lhs, rhs)
  return lhs:data().id < rhs:data().id
end

local function assert_data_meets_spec(node, spec)
  local spec_data = {
    name = spec.name,
    id = spec.id,
    path = spec.path,
    type = spec.type,
  }

  -- nil fields in spec are ignored to ease testing for specific fields
  if spec.kind then
    spec_data.extra = { kind = spec.kind }
  else
    spec_data.extra = node:data().extra
  end

  if spec.line_range then
    spec_data.range =
      { spec.line_range[1], node:data().range[2], spec.line_range[2], node:data().range[4] }
  else
    spec_data.range = node:data().range
  end

  assert.are.same(spec_data, node:data())
end

---Ensures that `spec` is represented by the `tree`
---@param namespace neotest.Tree
---@param spec any
local function assert_namespace_meets_spec(namespace, spec)
  spec.type = "namespace"
  assert_data_meets_spec(namespace, spec)

  if not spec.children then
    return
  end

  assert.are.equal(#spec.children, #namespace:children())

  for i = 1, #spec.children do
    local test_spec = spec.children[i]
    test_spec.id = spec.id .. "::" .. test_spec.name
    test_spec.path = spec.path
    test_spec.type = "test"
  end

  table.sort(spec.children, id_sorter)
  local tests = namespace:children()
  table.sort(tests, data_id_sorter)

  for i = 1, #spec.children do
    assert_data_meets_spec(tests[i], spec.children[i])
  end
end

---Ensures that `spec` is represented by the `tree`
---@param tree neotest.Tree
---@param spec any
function M.assert_tree_meets_spec(tree, spec)
  local namespaces = tree:children()

  assert.are.equal(#spec, #namespaces)
  for i = 1, #namespaces do
    local ns_spec = spec[i]
    ns_spec.id = spec.path .. "::" .. ns_spec.name
    ns_spec.path = spec.path
  end

  table.sort(spec, id_sorter)
  table.sort(namespaces, data_id_sorter)

  for i = 1, #namespaces do
    assert_namespace_meets_spec(namespaces[i], spec[i])
  end
end

function M.parse_tree_from_string(string)
  local fpath = assert(vim.fn.tempname()) .. ".cpp"
  lib.files.write(fpath, string)
  return parse_module.parse_positions(fpath)
end

function M.make_directory_tree(fname2content, dirpath)
  local project = MockProject:new(dirpath)
  project:set_contents(fname2content)
  return project:get_tree()
end

return M
