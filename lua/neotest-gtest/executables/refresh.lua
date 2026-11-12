local inventory = require("neotest-gtest.executables.inventory")

local M = {}

local directories = {}

local function rediscover_sources(sources)
  for source in pairs(sources) do
    if vim.uv.fs_stat(source) then
      -- Neotest has no public adapter refresh method. Invoke only its file
      -- discovery autocmd, leaving unrelated BufAdd handlers untouched.
      pcall(vim.api.nvim_exec_autocmds, "BufAdd", {
        group = "neotest.Client",
        pattern = source,
        modeline = false,
      })
    end
  end
end

local function queue_refresh(directory, name)
  if directory.closed then
    return
  end

  local entry = directory.executables[name]
  if not entry then
    return
  end

  entry.generation = entry.generation + 1
  local generation = entry.generation

  -- The binary changed, so its cached listing is stale. Rediscovery waits for
  -- the debounce below, so a link in progress does not start listings.
  inventory.invalidate(entry.executable)

  vim.defer_fn(function()
    if not directory.closed and entry.generation == generation then
      rediscover_sources(entry.sources)
    end
  end, 250)
end

---@param executable string
---@param source string
function M.track(executable, source)
  local parent = vim.fn.fnamemodify(executable, ":h")
  local name = vim.fn.fnamemodify(executable, ":t")
  local directory = directories[parent]

  if not directory then
    local watcher = vim.uv.new_fs_event()
    if not watcher then
      return
    end

    directory = { watcher = watcher, executables = {} }
    local started = watcher:start(parent, {}, function(err, filename)
      if err then
        return
      end

      vim.schedule(function()
        if filename then
          queue_refresh(directory, vim.fn.fnamemodify(filename, ":t"))
        else
          for executable_name in pairs(directory.executables) do
            queue_refresh(directory, executable_name)
          end
        end
      end)
    end)

    if not started then
      watcher:close()
      return
    end

    directories[parent] = directory
  end

  directory.executables[name] = directory.executables[name] or { sources = {}, generation = 0 }

  local entry = directory.executables[name]
  entry.executable = executable
  entry.sources[source] = true
end

---Rediscovers the given source files now, without waiting for a save or rebuild.
---Used after configuring an executable, so its compiled cases appear at once.
---@param sources table<string, boolean> Set of source file paths
function M.rediscover(sources)
  rediscover_sources(sources)
end

-- Used by the test registry reset so watchers do not cross test cases.
function M.reset()
  for _, directory in pairs(directories) do
    directory.closed = true
    directory.watcher:close()
  end

  directories = {}
end

return M
