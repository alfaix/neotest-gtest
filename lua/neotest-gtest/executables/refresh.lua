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
  directory.executables[name].sources[source] = true
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
