local utils = require("neotest-gtest.utils")
local lib = require("neotest.lib")
local parse = require("neotest-gtest.parse")
local Report = require("neotest-gtest.report")
local executables = require("neotest-gtest.executables")

local GTestNeotestAdapater = { name = "neotest-gtest" }
GTestNeotestAdapater.is_test_file = utils.is_test_file
GTestNeotestAdapater.discover_positions = parse.parse_positions

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
      -- TODO!!!
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
function GTestNeotestAdapater.build_spec(args)
  --`position` may be a directory, which could correspond to multiple GTest
  --executables. We therefore first build {executable -> nodes} structure, and
  --then create a separate spec for each executable
  local tree = args.tree
  local path = tree:data().path
  local root = utils.normalize_path(GTestNeotestAdapater.root(path))
  local ok, executable_paths, missing = GTestNeotestAdapater.find_executables(args.tree, root)
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
  local i = 0
  for executable, node_ids in pairs(executable_paths) do
    for _, node_id in ipairs(node_ids) do
      -- assumption: get_key looks for all children
      local node = tree:get_key(node_id)
      if node == nil then
        error(string.format("node_id %s not found", node_id))
      end
      local filters = table.concat(vim.tbl_flatten({ node2filters(node) }), ":")
      local logdir = utils.new_results_dir({ history_size = GTestNeotestAdapater.history_size })
      local results_path = string.format("%s/test_result_%d.json", logdir, i)
      local command = vim.tbl_flatten({
        executable,
        "--gtest_output=json:" .. results_path,
        "--gtest_filter=" .. filters,
        args.extra_args,
        -- gtest doesn't print colors when being redirected
        -- but neotest keeps the colors nice and shiny. Thanks, neotest!
        "--gtest_color=yes",
      })
      specs[#specs + 1] = { command = command, context = { results_path = results_path } }
    end
    i = i + 1
  end

  return specs
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return neotest.Result[]
function GTestNeotestAdapater.results(spec, result, tree)
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

local function set_summary_autocmd(config)
  local group = vim.api.nvim_create_augroup("NeotestGtestConfigureMarked", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "neotest-summary",
    group = group,
    callback = function(ctx)
      local buf = ctx.buf
      vim.api.nvim_buf_create_user_command(buf, "ConfigureGtest", function()
        executables.configure_executable()
      end, {})
      if config.mappings.configure ~= nil then
        vim.api.nvim_buf_set_keymap(
          buf,
          "n",
          config.mappings.configure_key,
          "<CMD>ConfigureGtest",
          { desc = "Select a Google Test executable for marked tests" }
        )
      end
    end,
  })
end

function GTestNeotestAdapater.setup(config)
  local default_config = {
    root = lib.files.match_root_pattern(
      "compile_commands.json",
      "compile_flags.txt",
      "WORKSPACE",
      ".clangd",
      "init.lua",
      "init.vim",
      "build",
      ".git"
    ),
    find_executables = require("neotest-gtest.executables").find_executables,
    history_size = 3,
    is_test_file = utils.is_test_file,
    mappings = { configure = nil },
    filter_dir = function(name, rel_path, root)
      return true
    end,
  }
  config = vim.tbl_deep_extend("keep", config, default_config)

  GTestNeotestAdapater.root = config.root
  GTestNeotestAdapater.filter_dir = config.filter_dir
  GTestNeotestAdapater.history_size = config.history_size
  GTestNeotestAdapater.is_test_file = config.is_test_file
  GTestNeotestAdapater.find_executables = config.find_executables

  set_summary_autocmd(config)

  return GTestNeotestAdapater
end

return GTestNeotestAdapater
