local assert = require("luassert")
local it = require("nio.tests").it
local nio = require("nio")
local lib = require("neotest.lib")
local neotest = require("neotest")
local inventory = require("neotest-gtest.executables.inventory")
local controller = require("tests.utils.controller")

describe("compiled inventory refresh", function()
  it("adds runtime leaves after a rebuild without configuring or saving again", function()
    controller.setup()

    local state = controller.state
    local source = state:mkid("test_two.cpp")
    local source_id = source .. "::ParamFixture::Positive"
    local first_name = "First/ParamFixture.Positive/0"
    local new_name = "First/ParamFixture.Positive/1"
    local executable = assert(vim.fn.tempname())
    local names = { first_name }
    local old_list = inventory.list

    lib.files.write(executable, "first build")

    inventory.list = function(path)
      assert.equals(executable, path)
      return names
    end

    state:configure_executables({ [executable] = { source } })

    nio.scheduler()
    vim.api.nvim_exec_autocmds("BufWritePost", { pattern = source, modeline = false })

    for _ = 1, 100 do
      local positions = neotest.state.positions(state.adapter_id)
      if positions and positions:get_key(source_id .. "::" .. first_name) then
        break
      end

      nio.sleep(20)
    end

    local initial = assert(neotest.state.positions(state.adapter_id))
    assert.is_not_nil(initial:get_key(source_id .. "::" .. first_name))
    assert.is_nil(initial:get_key(source_id .. "::" .. new_name))

    nio.scheduler()
    local buffer = vim.fn.bufnr(source)
    if buffer > 0 and vim.api.nvim_buf_is_loaded(buffer) then
      vim.api.nvim_buf_delete(buffer, { force = true })
    end
    assert.equals(0, vim.fn.bufloaded(source))

    names = { first_name, new_name }
    lib.files.write(executable, "second build")

    local refreshed
    for _ = 1, 100 do
      local positions = neotest.state.positions(state.adapter_id)
      refreshed = positions and positions:get_key(source_id .. "::" .. new_name)
      if refreshed then
        break
      end

      nio.sleep(20)
    end

    inventory.list = old_list

    assert.is_not_nil(refreshed)
    assert.equals(executable, state:_get_node_executable(source_id))
  end)

  it("discovers a source test changed on disk when its configured binary rebuilds", function()
    controller.setup()
    nio.scheduler()

    local state = controller.state
    local source = state:mkid("test_refresh.cpp")
    local executable = assert(vim.fn.tempname())

    lib.files.write(source, "TEST(Refresh, First) {}\n")
    lib.files.write(executable, "first build")

    nio.scheduler()
    vim.api.nvim_exec_autocmds("BufAdd", { pattern = source, modeline = false })

    for _ = 1, 100 do
      local positions = neotest.state.positions(state.adapter_id)
      if positions and positions:get_key(source .. "::Refresh::First") then
        break
      end

      nio.sleep(20)
    end

    state:configure_executables({ [executable] = { source } })
    assert.equals(0, vim.fn.bufloaded(source))

    lib.files.write(source, "TEST(Refresh, First) {}\nTEST(Refresh, Second) {}\n")
    lib.files.write(executable, "second build")

    local refreshed
    for _ = 1, 100 do
      local positions = neotest.state.positions(state.adapter_id)
      refreshed = positions and positions:get_key(source .. "::Refresh::Second")
      if refreshed then
        break
      end

      nio.sleep(20)
    end

    nio.scheduler()
    vim.fn.delete(source)

    assert.is_not_nil(refreshed)
    assert.equals(0, vim.fn.bufloaded(source))
  end)

  it("adds runtime leaves when an executable is configured, without saving", function()
    controller.setup()
    nio.scheduler()

    local state = controller.state
    local source = state:mkid("test_two.cpp")
    local source_id = source .. "::ParamFixture::Positive"
    local runtime_name = "First/ParamFixture.Positive/0"
    local executable = assert(vim.fn.tempname())
    local old_list = inventory.list

    lib.files.write(executable, "built")
    inventory.list = function(path)
      assert.equals(executable, path)
      return { runtime_name }
    end

    state:configure_executables({ [executable] = { source } })

    local leaf
    for _ = 1, 100 do
      local positions = neotest.state.positions(state.adapter_id)
      leaf = positions and positions:get_key(source_id .. "::" .. runtime_name)
      if leaf then
        break
      end

      nio.sleep(20)
    end

    inventory.list = old_list

    assert.is_not_nil(leaf)
  end)

  it("lists a rebuilt executable once when several open files share it", function()
    controller.setup()
    nio.scheduler()

    local state = controller.state
    local first = state:mkid("test_two.cpp")
    local second = state:mkid("test_typed.cpp")
    local executable = assert(vim.fn.tempname())
    local counter = executable .. ".count"

    -- Writes an executable that appends one line to `counter` per listing.
    local function write_counting_executable(listing)
      local script =
        string.format("#!/bin/sh\necho run >> '%s'\nprintf '%%s' '%s'\n", counter, listing)

      lib.files.write(executable, script)
      assert.is_true(vim.uv.fs_chmod(executable, 493))
    end

    local function listings()
      local count = 0
      local file = io.open(counter, "r")

      if file == nil then
        return 0
      end

      for _ in file:lines() do
        count = count + 1
      end

      file:close()
      return count
    end

    write_counting_executable("First/ParamFixture.Positive/0\n")
    state:configure_executables({ [executable] = { first, second } })

    nio.scheduler()
    vim.api.nvim_exec_autocmds("BufWritePost", { pattern = first, modeline = false })
    vim.api.nvim_exec_autocmds("BufWritePost", { pattern = second, modeline = false })

    for _ = 1, 100 do
      if listings() > 0 then
        break
      end

      nio.sleep(20)
    end

    -- Let the initial discovery settle before measuring the rebuild.
    nio.sleep(500)
    local before_rebuild = listings()

    write_counting_executable("First/ParamFixture.Positive/0\nFirst/ParamFixture.Positive/1\n")

    for _ = 1, 100 do
      if listings() > before_rebuild then
        break
      end

      nio.sleep(20)
    end

    -- Wait past the refresh debounce so any extra listings have time to start.
    nio.sleep(800)

    assert.equals(before_rebuild + 1, listings())
  end)
end)
