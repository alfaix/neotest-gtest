local M = {}

---@param strategy string
---@param adapter string
---@param command string
function M.strategy(strategy, adapter, command)
  local config = {
    dap = function()
      return {
        name = "Debug GTest",
        type = adapter,
        request = "launch",
        program = command[1],
        args = { unpack(command, 2) },
      }
    end,
  }
  if config[strategy] then
    return config[strategy]()
  end
end

return M
