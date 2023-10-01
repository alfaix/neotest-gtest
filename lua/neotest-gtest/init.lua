-- TODO
-- 1. documentation + tests
-- 2. UI improvements: vim.select UI, allow clearing cache, etc.
-- 3. Detect outdated executable
-- 4. TEST_P
-- 5. Debugging

local utils = require("neotest-gtest.utils")
local lib = require("neotest.lib")
local parse = require("neotest-gtest.parse")
local Report = require("neotest-gtest.report")
local Cache = require("neotest-gtest.cache")
local runners = require("neotest-gtest.runner")
local dap = require("neotest-gtest.dap")

-- treesitter matches TEST macros as function definitions
-- treesitter cannot possibly know about macros defined in other files, so this
-- is the best we can do. It works pretty well though.
-- under C standard, they are valid definitions with implicit int return type
-- (and with proper compiler flags the CPP code should also compile which should
--  mean that treesitter should continue to parse these as function definitions)
-- Thus, we match all function definitions that meet ALL of the following criteria:
-- * Named TEST/TEST_F/TEST_P (#any-of)
-- * Do not declare a return type (!type)
-- * Only have two parameters (. anchors)
-- * Both parameters are unnamed (!declarator)
-- * Both parameters' type is a simple type_identifier, i.e., no references
--   or cv-qualifiers or templates (type: (type_identifier))
-- The first parameter is the test suite, the second one is the test case
-- The name of the "function" is the test kind (TEST/TEST_F/TEST_P)
local query = [[
((function_definition
	declarator: (
      function_declarator
        declarator: (identifier) @test.kind
      parameters: (
        parameter_list
          . (parameter_declaration type: (type_identifier) !declarator) @namespace.name
          . (parameter_declaration type: (type_identifier) !declarator) @test.name
          .
      )
    )
    !type
)
(#any-of? @test.kind "TEST" "TEST_F" "TEST_P"))
@test.definition
]]

query = vim.treesitter.query.parse("cpp", query)

local GTestNeotestAdapter = { name = "neotest-gtest" }
GTestNeotestAdapter.is_test_file = utils.is_test_file
function GTestNeotestAdapter.discover_positions(path)
  return parse.parse_positions(path, query)
end

-- @param position neotest.Tree position to create a filter to
-- @returns string
local function position2filter(position)
  local data = position:data()
  local type = data.type
  local posid = data.id
  if type == "test" then
    local test_kind = data.extra.kind
    if test_kind == "TEST_P" then
      -- TODO!!!
      error("TEST_P is not yet supported, sorry :(")
    else
      local parts = vim.split(posid, "::", { plain = true })
      assert(#parts == 3, "bad position")
      -- local file = parts[1]
      local namespace = parts[2]
      local test_name = parts[3]
      return string.format("%s.%s", namespace, test_name)
    end
  elseif type == "namespace" then
    local parts = vim.split(posid, "::", { plain = true })
    assert(#parts == 2, "bad position")
    return data.name .. ".*"
  elseif type == "file" then
    -- Google Test does not support file filters. We collect all tests in
    -- the file and run it that way. We can also only run the namespace,
    -- however, Google Test does not restrict namespaces to be contained in
    -- a single translation unit, and neither should we.
    local filters = {}
    for _, namespace in ipairs(position:children()) do
      for _, test in ipairs(namespace:children()) do
        filters[#filters + 1] = position2filter(test)
      end
    end
    return table.concat(filters, ":")
  elseif type == "dir" then
    -- TODO figure this out. If all tests are under one runner, no issues
    -- running this. If under multiple, either need to run multiple commands
    -- or write a wrapper script (in python, probably).
    -- If runners for some of them are not known, unclear what to do. Asking
    -- for every file is probably not a great idea
    return nil
  else
    error("unknown position type " .. type)
  end
end

function GTestNeotestAdapter.update_cache(root, executable, runner)
  local cache, new = Cache:cache_for(root)
  if new then
    cache:load_runners(cache:list_runners())
  end
  cache:update(executable, runner)
end

function GTestNeotestAdapter.build_spec(args)
  local position = args.tree
  local path = position:data().path
  local root = GTestNeotestAdapter.root(path)
  local cache, new = Cache:cache_for(root)
  if new then
    runners.load_runners(cache:list_runners())
  end

  local filter = position2filter(position)
  if #filter == 0 then
    error("Did not run tests: no tests selected to run")
  end

  local runner, err = runners.ui.runner_for(path)
  if runner == nil and err == nil then -- requested a new one
    runner, err = runners.ui.new({ paths = { path } })
  elseif runner ~= nil then
    assert(err == nil, err)
    -- If the runner was chosen interactively, this is needed. Otherwise,
    -- i.e., if the runner has been selected before, this does nothing
    -- this never fails
    runner:add_path(path)
  elseif runner == nil then
    error("GTest executable not specified or does not exist")
  else
    error("Did not run tests: " .. err)
  end
  cache:update(runner:executable(), runner:to_json())
  cache:flush(false)

  local logdir = cache:new_results_dir()
  local results_path = logdir .. "/test_result.json"
  local command = vim.tbl_flatten({
    runner:executable(),
    "--gtest_output=json:" .. results_path,
    "--gtest_filter=" .. filter,
    args.extra_args,
    -- gtest doesn't print colors when begin redirected
    -- but neotest keeps the colors nice and shiny. Thanks, neotest!
    "--gtest_color=yes",
  })
  return {
    command = command,
    context = { results_path = results_path },
    strategy = dap.strategy(
      args.strategy,
      GTestNeotestAdapter.debug_adapter,
      command
    ),
  }
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return neotest.Result[]
function GTestNeotestAdapter.results(spec, result, tree)
  -- nothing ran
  local success, data = pcall(lib.files.read, spec.context.results_path)
  if not success then
    vim.notify(
      string.format(
        [[Gtest executable failed to produce a result. Command: %s, exit code: %d, output at: %s\n
            Please make sure any additional arguments supplied are correct and check the output for additional info.]],
        table.concat(spec.command, " "),
        result.code,
        result.output
      )
    )
    return {}
  end
  local gtest_output = vim.json.decode(data) or { testsuites = {} }
  local reports = {}
  for _, testsuite in ipairs(gtest_output.testsuites) do
    for _, test in ipairs(testsuite.testsuite) do
      local report = Report:new(test, tree)
      reports[report:position_id()] = report:to_neotest_report(result.output)
    end
  end
  return reports
end

function GTestNeotestAdapter.setup(config)
  local default_config = {
    debug_adapter = "codelldb",
    root = lib.files.match_root_pattern(
      "compile_commands.json",
      "compile_flags.txt",
      ".clangd",
      "init.lua",
      "init.vim",
      "build", ".git"
    ),
    is_test_file = utils.is_test_file
  }
  config = vim.tbl_deep_extend("keep", config, default_config)
  GTestNeotestAdapter.debug_adapter = config.debug_adapter
  GTestNeotestAdapter.root = config.root
  GTestNeotestAdapter.is_test_file = config.is_test_file
  return GTestNeotestAdapter
end


return GTestNeotestAdapter
