local M = {}
local nio = require("nio")

local run = nio.wrap(function(command, options, callback)
  vim.system(command, options, callback)
end, 3)

local DEFAULT_TIMEOUT_MS = 30000

---List the tests registered in a compiled Google Test executable.
---@async
---@param executable string
---@param opts? { timeout_ms?: integer }
---@return string[]
function M.list(executable, opts)
  local timeout_ms = (opts and opts.timeout_ms) or DEFAULT_TIMEOUT_MS
  local result = run({ executable, "--gtest_list_tests" }, { text = true, timeout = timeout_ms })

  if result.code == 124 then
    error(string.format("%s --gtest_list_tests timed out after %d ms", executable, timeout_ms))
  end

  if result.code ~= 0 then
    error(string.format("%s --gtest_list_tests exited with code %d", executable, result.code))
  end

  return M.parse_list(result.stdout)
end

---Parse full test names from Google Test's --gtest_list_tests output.
---For example:
---  Running main() from .../gtest_main.cc
---  TypedFixture/Small.  # TypeParam = int
---    Passes  # GetParam() = 1
---    FailsWhenRequested
---  Second/PatternFixture/1.  # TypeParam = int
---    Works
---becomes TypedFixture/Small.Passes, TypedFixture/Small.FailsWhenRequested,
---and Second/PatternFixture/1.Works.
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

---Group an executable's runtime names by source declaration.
---This is the second phase of discovery: source parsing creates positions,
---then the compiled inventory adds generated cases beneath those positions.
---Parsed shapes:
---  First/ParamFixture.Positive/0 -> TEST_P(ParamFixture, Positive)
---  TypedFixture/Small.Passes -> TYPED_TEST(TypedFixture, Passes)
---  Second/PatternFixture/1.Works -> TYPED_TEST_P(PatternFixture, Works)
---A runtime name with multiple matching source declarations raises an error.
---@param tree neotest.Tree Source-only position tree
---@param names string[] Full runtime names returned by parse_list
---@return table<string, string[]> by_source Source position ID to runtime names
---@return string[] unmatched Runtime names with no matching source in the tree
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
    -- "First/ParamFixture.Positive/0" -> "First/ParamFixture", "Positive/0".
    local suite, test = runtime_name:match("^([^%.]+)%.([^%.]+)$")
    local source_name
    local kind

    if suite and test and test:find("/", 1, true) then
      -- "First/ParamFixture.Positive/0" -> "ParamFixture.Positive".
      source_name = (suite:match("([^/]+)$") or suite) .. "." .. test:match("^([^/]+)")
      kind = "TEST_P"
    elseif suite and test then
      -- "Second/PatternFixture/1.Works" -> "PatternFixture.Works";
      -- "TypedFixture/Small.Passes" -> "TypedFixture.Passes".
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
