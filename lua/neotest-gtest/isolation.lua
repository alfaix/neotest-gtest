local lib = require("neotest.lib")
local nio = require("nio")

local M = {}

-- Neotest accepts a custom strategy returning one Process for a selection.
-- Its runner fills missing positions after each spec, so the child processes
-- must finish before the adapter publishes the combined result.
function M.strategy(spec)
  local integrated = require("neotest.client.strategies.integrated")
  local cases = spec.context.isolated_cases
  local output_path = nio.fn.tempname()
  local active
  local complete = false
  local stopped = false

  return {
    is_complete = function()
      return complete
    end,
    output = function()
      return output_path
    end,
    output_stream = function()
      return function()
        return nil
      end
    end,
    attach = function()
      if active then
        active.attach()
      end
    end,
    stop = function()
      stopped = true
      if active then
        active.stop()
      end
    end,
    result = function()
      local output = {}
      local exit_code = 0

      for _, case in ipairs(cases) do
        if stopped then
          break
        end

        case.env = spec.env
        case.cwd = spec.cwd
        case.strategy = {}

        active = integrated(case)
        local code = active.result()
        local child_output = active.output()
        case.process_result = { code = code, output = child_output }

        local ok, data = pcall(lib.files.read, child_output)
        if ok then
          output[#output + 1] = data
        end

        if code ~= 0 then
          exit_code = 1
        end

        active = nil
      end

      lib.files.write(output_path, table.concat(output, "\n"))
      complete = true
      return stopped and 130 or exit_code
    end,
  }
end

return M
