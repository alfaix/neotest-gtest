local utils = require("neotest-gtest.utils")
local lib = require("neotest.lib")
local parse = require("neotest-gtest.parse")
local Report = require("neotest-gtest.report")
local marks = require("neotest-gtest.marks")

local GTestNeotestAdapter = { name = "neotest-gtest" }
GTestNeotestAdapter.is_test_file = utils.is_test_file
GTestNeotestAdapter.discover_positions = parse.parse_positions
local dap = require("neotest-gtest.dap")

---@param node neotest.Tree position to create a filter to
---@return string | string[] filters String or potentially nested list of strings.
---        flatten to get just a list of strings.
local function node2filters(node)
  local data = node:data()
  local type = data.type
  local posid = data.id
  if type == "test" then
    local test_kind = data.extra.kind
    if test_kind == "TEST_P" then
      -- TODO: figure this out (will have to query executables and do
      -- best-effort matching, probably)
      error("TEST_P is not yet supported, sorry :(")
    else
      local parts = vim.split(posid, "::", { plain = true })
      -- file::namespace::test_name
      assert(#parts == 3, "bad node")
      local namespace = parts[2]
      local test_name = parts[3]
      return string.format("%s.%s", namespace, test_name)
    end
  elseif type == "namespace" then
    return data.name .. ".*"
  elseif type == "file" or type == "dir" then
    local filters = {}
    -- run child namespaces: if a namespaces exist in multiple files, this can
    -- lead to running tests which should not have been run. IDK who would do
    -- that though.
    for _, child in ipairs(node:children()) do
      filters[#filters + 1] = node2filters(child)
    end
    return filters
  else
    error("unknown node type " .. type)
  end
end

---@param args neotest.RunArgs
---@return nil | neotest.RunSpec[]
function GTestNeotestAdapter.build_spec(args)
  --`position` may be a directory, which could correspond to multiple GTest
  --executables. We therefore first build {executable -> nodes} structure, and
  --then create a separate spec for each executable
  local tree = args.tree
  local path = tree:data().path
  local root = utils.normalize_path(GTestNeotestAdapter.root(path))
  -- FIXME
  local ok, executable_paths, missing = executables.find_executables(args.tree, root)
  if not ok then
    vim.notify(
      string.format(
        "Some nodes do not have a corresponding GTest executable set. Please "
          .. "configure them by mraking them and then running :ConfigureGtest "
          .. "in the summary window. Nodes: %s",
        vim.tbl_map(function(node)
          return node:data().id
        end, missing)
      ),
      vim.log.levels.ERROR
    )
    return nil
  end

  local specs = {}
  for executable, node_ids in pairs(executable_paths) do
    for _, node_id in ipairs(node_ids) do
      -- assumption: get_key looks for all children
      local node = tree:get_key(node_id)
      if node == nil then
        error(string.format("node_id %s not found", node_id))
      end
      local filters = table.concat(vim.tbl_flatten({ node2filters(node) }), ":")
      local logdir = utils.new_results_dir({ history_size = GTestNeotestAdapter.history_size })
      local results_path = string.format("%s/test_result_%d.json", logdir, #specs)
      local command = vim.tbl_flatten({
        executable,
        "--gtest_output=json:" .. results_path,
        "--gtest_filter=" .. filters,
        args.extra_args,
        -- By default, gtest doesn't print colors when being redirected to a file
        -- but neotest keeps the colors nice and shiny. Thanks, neotest!
        "--gtest_color=yes",
      })
      specs[#specs + 1] = {
        command = command,
        context = { results_path = results_path },
        strategy = dap.strategy(args.strategy, GTestNeotestAdapter.debug_adapter, command),
      }
    end
  end
  -- FIXME:
  -- Incorrect specs: one spec per each test (at least with debug) even if exe
  -- is the same
  return specs
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
      -- TODO generally works, short report of `report` is not really short, not
      -- sure why. Can't call vim.notify() here because async/scheduling bullshit
      reports[report:position_id()] = report:to_neotest_report(result.output)
    end
  end
  return reports
end

function GTestNeotestAdapter.setup(config)
  require("neotest-gtest.config").setup(config)
end

return GTestNeotestAdapter
