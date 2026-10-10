local M = {}
local lib = require("neotest.lib")

---List the tests registered in a compiled Google Test executable.
---@async
---@param executable string
---@return string[]
function M.list(executable)
  local code, result = lib.process.run({ executable, "--gtest_list_tests" }, { stdout = true })

  if code ~= 0 then
    error(string.format("%s --gtest_list_tests exited with code %d", executable, code))
  end

  return M.parse_list(result.stdout)
end

---Parse full test names from Google Test's --gtest_list_tests output.
---@param output string
---@return string[]
function M.parse_list(output)
  local names = {}
  local suite

  for line in output:gmatch("[^\r\n]+") do
    local value = vim.trim(line:gsub("%s+#.*$", ""))

    if line:match("^%S") then
      suite = value:match("^(.-)%.$")
    elseif suite and value ~= "" then
      names[#names + 1] = suite .. "." .. value
    end
  end

  return names
end

---Group generated cases by their source declaration.
---@param tree neotest.Tree
---@param names string[]
---@return table<string, string[]>, string[]
function M.map_source(tree, names)
  local by_source = {}
  local sources_by_name = {}

  for _, node in tree:iter_nodes() do
    local data = node:data()

    local kind = data.extra and data.extra.kind
    if
      data.type == "test"
      and (kind == "TEST_P" or kind == "TYPED_TEST" or kind == "TYPED_TEST_P")
    then
      by_source[data.id] = {}

      local source_name = node:parent():data().name .. "." .. data.name
      sources_by_name[source_name] = sources_by_name[source_name] or {}
      table.insert(sources_by_name[source_name], { id = data.id, kind = kind })
    end
  end

  local unmatched = {}

  for _, runtime_name in ipairs(names) do
    local suite, test = runtime_name:match("^([^%.]+)%.([^%.]+)$")
    local source_name
    local kind

    if suite and test and test:find("/", 1, true) then
      source_name = (suite:match("([^/]+)$") or suite) .. "." .. test:match("^([^/]+)")
      kind = "TEST_P"
    elseif suite and test then
      local fixture = suite:match("([^/]+)/[^/]+$")
      source_name = fixture and fixture .. "." .. test
    end

    local sources = source_name and sources_by_name[source_name]
    local ids = {}

    for _, source in ipairs(sources or {}) do
      local matches_value_parameter = kind == "TEST_P" and source.kind == kind
      local matches_type_parameter = kind == nil and source.kind ~= "TEST_P"

      if matches_value_parameter or matches_type_parameter then
        ids[#ids + 1] = source.id
      end
    end

    if #ids == 0 then
      unmatched[#unmatched + 1] = runtime_name
    else
      assert(#ids == 1, "ambiguous generated source for " .. runtime_name)
      table.insert(by_source[ids[1]], runtime_name)
    end
  end

  return by_source, unmatched
end

return M
