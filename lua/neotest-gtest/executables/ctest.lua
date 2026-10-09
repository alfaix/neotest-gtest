local nio = require("nio")
local neotest = require("neotest")
local lib = require("neotest.lib")
local GlobalRegistry = require("neotest-gtest.executables.global_registry")
local utils = require("neotest-gtest.utils")

local ADAPTER_PREFIX = "neotest-gtest:"

local M = {}

local function find_compile_db(file)
  for dir in vim.fs.parents(file) do
    for _, candidate in ipairs({
      dir .. "/compile_commands.json",
      dir .. "/build/compile_commands.json",
    }) do
      if utils.fexists(candidate) then
        return candidate
      end
    end
  end
end

local function canonical(path)
  return vim.uv.fs_realpath(path) or path
end

local function parse_compile_db(json)
  local by_file = {}
  for _, entry in ipairs(vim.json.decode(json)) do
    local command = entry.command or table.concat(entry.arguments, " ")
    by_file[canonical(entry.file)] = {
      directory = entry.directory,
      target = command:match("CMakeFiles/([^/]+)%.dir/"),
    }
  end
  return by_file
end

---@return table<string, {directory: string, target: string?}> file -> where it was compiled
local function load_compile_db(path)
  return parse_compile_db(lib.files.read(path))
end

local function parse_ctest_json(json)
  local exe2tests = {}
  for _, test in ipairs(vim.json.decode(json).tests) do
    local command = test.command or {}
    for _, arg in ipairs(command) do
      local filter = arg:match("^%-%-gtest_filter=(.*)$")
      if filter ~= nil then
        exe2tests[command[1]] = exe2tests[command[1]] or {}
        exe2tests[command[1]][filter] = true
      end
    end
  end
  return exe2tests
end

---@return table<string, table<string, boolean>> executable -> set of "Suite.Test"
local function ctest_tests(build_dir)
  local code, result = lib.process.run(
    { "ctest", "--test-dir", build_dir, "--show-only=json-v1" },
    { stdout = true }
  )
  if code ~= 0 then
    error("ctest --show-only failed in " .. build_dir)
  end
  return parse_ctest_json(result.stdout)
end

local function better(exe, hits, best, best_hits, target)
  if hits ~= best_hits then
    return hits > best_hits
  end
  local exe_is_target = vim.fs.basename(exe) == target
  if exe_is_target ~= (vim.fs.basename(best) == target) then
    return exe_is_target
  end
  return exe < best
end

---@param tests string[] "Suite.Test" names parsed from one source file
local function pick_executable(exe2tests, tests, target)
  local best, best_hits = nil, 0
  for exe, known in pairs(exe2tests) do
    local available = {}
    for runtime_name in pairs(known) do
      available[runtime_name] = true
      local source_name = runtime_name:match("([^/]+%.[^/]+)/[^/]+$")
      if source_name then
        available[source_name] = true
      end
    end
    local hits = 0
    for _, name in ipairs(tests) do
      if available[name] then
        hits = hits + 1
      end
    end
    local plausible = hits > 0 or (#tests == 0 and vim.fs.basename(exe) == target)
    if plausible and (best == nil or better(exe, hits, best, best_hits, target)) then
      best, best_hits = exe, hits
    end
  end
  return best
end

---@param node neotest.Tree a "file" node
local function tests_in_file(node)
  local tests = {}
  for _, child in node:iter_nodes() do
    if child:data().type == "test" then
      local parts = vim.split(child:data().id, "::", { plain = true })
      tests[#tests + 1] = parts[2] .. "." .. parts[3]
    end
  end
  return tests
end

local function cached(cache, key, load)
  if cache[key] == nil then
    local ok, value = pcall(load, key)
    cache[key] = { ok = ok, value = value }
  end
  local hit = cache[key]
  if not hit.ok then
    error(hit.value, 0)
  end
  return hit.value
end

function M.resolve_file(file, tests, cache)
  file = canonical(file)
  local db_path = find_compile_db(file)
  if db_path == nil then
    return nil, "no compile_commands.json above " .. file
  end
  local entry = cached(cache.db, db_path, load_compile_db)[file]
  if entry == nil then
    return nil, "not in " .. db_path
  end
  local ok, exe2tests = pcall(cached, cache.ctest, entry.directory, ctest_tests)
  if not ok then
    return nil, exe2tests
  end
  local exe = pick_executable(exe2tests, tests, entry.target)
  if exe == nil then
    return nil, "no binary in " .. entry.directory .. " contains its tests"
  end
  return exe
end

local function configure_root(adapter_id)
  local tree = neotest.state.positions(adapter_id)
  local registry = GlobalRegistry:for_dir(adapter_id:sub(#ADAPTER_PREFIX + 1))
  local mapped, unmapped = 0, {}
  local cache = { db = {}, ctest = {} }
  for _, node in tree:iter_nodes() do
    if node:data().type == "file" then
      local file = node:data().path
      local exe, reason = M.resolve_file(file, tests_in_file(node), cache)
      if exe ~= nil then
        registry:update_executable(file, exe)
        mapped = mapped + 1
      else
        unmapped[#unmapped + 1] = file .. " (" .. reason .. ")"
      end
    end
  end
  return mapped, unmapped
end

function M.configure_all()
  return nio.run(function()
    for _, adapter_id in ipairs(neotest.state.adapter_ids()) do
      if vim.startswith(adapter_id, ADAPTER_PREFIX) then
        local mapped, unmapped = configure_root(adapter_id)
        local msg = string.format("neotest-gtest: mapped %d files", mapped)
        if #unmapped > 0 then
          msg = msg .. ", unresolved: " .. table.concat(unmapped, ", ")
        end
        utils.schedule_notify(msg, vim.log.levels.INFO)
      end
    end
  end, function(ok, err)
    if not ok then
      vim.schedule(function()
        vim.notify(tostring(err), vim.log.levels.ERROR)
      end)
    end
  end)
end

M._parse_compile_db = parse_compile_db
M._parse_ctest_json = parse_ctest_json
M._pick_executable = pick_executable

return M
