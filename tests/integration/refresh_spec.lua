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

    vim.fn.delete(source)

    assert.is_not_nil(refreshed)
    assert.equals(0, vim.fn.bufloaded(source))
  end)
end)
