local GlobalRegistry = require("neotest-gtest.executables.global_registry")

local M = {}

---@param node neotest.Tree Test node to perform the lookup for.
---@return {string: string[]} | nil results executable path -> node_ids[]
---@return neotest.Tree[] | nil not_found List of nodes for which no executables
---        could be found (potentially incomplete)
function M.find_executables(node, root)
  local registry = GlobalRegistry:for_dir(root)
end

---Lists all executables that are registered for at least one of node in a tree
---under any of `roots`.
function M.list_executables(roots)
  if type(roots) == "string" then
    roots = { roots }
  end
  return GlobalRegistry:list_executables(roots)
end

---Prompts the user to enter executable path and sets it for all `positions`.
---@param positions string[] forwarded to `set_all`
local function input_executable(positions)
  vim.ui.input({
    prompt = "Enter path to the executable which will run marked tests: ",
    completion = "file",
  }, function(path)
    if path ~= nil then
      set_executable_for_positions(path, positions)
    end
  end)
end

local function get_marked_positions()
  local summary = require("neotest").summary
  local positions = {}
  local prefix = "neotest-gtest:"
  for adapter, marked in pairs(summary.marked()) do
    if vim.startswith(adapter, prefix) then
      for _, position in pairs(marked) do
        positions[#positions + 1] = position
      end
    end
  end
  return positions
end

---Prompts the user to configure executable for all currently marked nodes.
---Asks the user to choose an existing executable, enter a new path, or clear
---the mapping for all marked nodes.
---@see neotest.consumers.summary.marked
function M.configure_executable()
  local positions = get_marked_positions()
  if #positions == 0 then
    vim.notify(
      "Please mark the tests (or namespaces, files, dirs) first and then call :ConfigureGtest",
      vim.log.levels.INFO
    )
    return
  end
  local roots = vim.tbl_map(position_root, positions)

  local choices = list_executables(roots)
  choices[#choices + 1] = "Remove bindings for selected nodes"
  choices[#choices + 1] = "Enter path..."
  vim.ui.select(choices, {
    prompt = "Select path to the executable which will run marked tests:",
  }, function(chosen, idx)
    if idx < #choices - 1 then
      set_executable_for_positions(chosen, positions)
    elseif idx == #choices - 1 then -- choice == Remove bindings
      set_executable_for_positions(nil, positions)
    else -- choice == Enter path...
      input_executable(positions)
    end
  end)
  summary.clear_marked({ adapter = "neotest-gtest" })
end

return M
