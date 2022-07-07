local utils = require("neotest-gtest.utils")
local lib = require("neotest.lib")
local parse = require("neotest-gtest.parse")
local Report = require("neotest-gtest.report")

-- treesitter matches TEST macros as function definitions
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

query = vim.treesitter.query.parse_query("cpp", query)

local GTestNeotestAdapater = {name = "neotest-gtest"}
GTestNeotestAdapater.root = lib.files.match_root_pattern(
    "compile_commands.json", ".clangd", "init.lua", "init.vim", "build", ".git" -- TODO something else?
)

GTestNeotestAdapater.is_test_file = utils.is_test_file
function GTestNeotestAdapater.discover_positions(path)
    -- local project_root = GTestNeotestAdapater.root(path)
    -- local gtest_executable = utils.get_gtest_executable(project_root)
    return parse.parse_positions(path, query)
end

-- @param position neotest.Tree position to create a filter to
-- @returns string that
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
            local parts = vim.split(posid, "::", {plain = true})
            assert(#parts == 3, "bad position")
            -- local file = parts[1]
            local namespace = parts[2]
            local test_name = parts[3]
            return string.format("%s.%s", namespace, test_name)
        end
    elseif type == "namespace" then
        local parts = vim.split(posid, "::", {plain = true})
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
    else
        error("unknown position type " .. type)
    end
end

function GTestNeotestAdapater.build_spec(args)
    local logdir = utils.test_results_dir()
    local results_path = logdir .. "/test_result.json"
    local position = args.tree
    local filter = position2filter(position)
    -- completion will be relative to cwd() anyway
    local executable = utils.get_gtest_executable(vim.fn.getcwd())
    if executable == nil then
        -- error already reported
        return nil
    end
    local command = vim.tbl_flatten({
        executable, "--gtest_output=json:" .. results_path,
        "--gtest_filter=" .. filter, args.extra_args,
        -- gtest doesn't print colors when begin redirected
        -- but neotest keeps the colors nice and shiny. Thanks, neotest!
        "--gtest_color=yes"
    })
    return {
        command = command,
        context = {results_path = results_path, tree = args.tree}
    }
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@return neotest.Result[]
function GTestNeotestAdapater.results(spec, result)
    local success, data = pcall(lib.files.read, spec.context.results_path)
    if not success then
        vim.notify(string.format(
            [[Gtest executable failed to produce a result. Command: %s, exit code: %d, output at: %s\n
            Please make sure any additional arguments supplied are correct and check the output for additional info.]],
            table.concat(spec.command, " "), result.code, result.output))
        return {}
    end
    local gtest_output = vim.json.decode(data) or {testsuites = {}}
    local reports = {}
    for _, testsuite in ipairs(gtest_output.testsuites) do
        for _, test in ipairs(testsuite.testsuite) do
            local report = Report:new(test, spec.context.tree)
            reports[report:position_id()] =
                report:to_neotest_report(result.output)
        end
    end
    return reports
end

return GTestNeotestAdapater
