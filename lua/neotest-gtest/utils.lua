local async = require("plenary.async")
local Path = require("plenary.path")
local scandir = require("plenary.scandir")
local M = {}

M.test_extensions = {
    ["cpp"] = true,
    ["cc"] = true,
    ["cxx"] = true,
    ["c++"] = true
}

local function fexists(path)
    local stat, e = vim.loop.fs_stat(path)
    if e then return false, e end
    if stat.type == "file" then return true, nil end
    -- TODO check it's executable? permissions and shit
    return false,
           string.format("Expected regular file, found %s instead", stat.type)
end

function M.is_test_file(file_path)
    local elems = vim.split(file_path, Path.path.sep, {plain = true})
    local filename = elems[#elems]
    if filename == "" then -- directory
        return false
    end
    local extsplit = vim.split(filename, ".", {plain = true})
    local extension = extsplit[#extsplit]
    local fname_last_part = extsplit[#extsplit - 1]
    local result = M.test_extensions[extension] and
                       (vim.startswith(filename, "test_") or
                           vim.endswith(fname_last_part, "_test"))
    return result
end

M.executables = {}
M.last_chosen = nil

local function add_gtest_executable(path, root)
    path = Path:new(path):normalize()
    local abs = Path:new(path):absolute()
    if abs ~= path then path = Path:new(root, path).filename end
    local _, err = fexists(path)
    if err then
        vim.notify(
            string.format("Failed to run executable at %s: %s", path, err), 3)
        path = nil
    elseif not vim.tbl_contains(M.executables, path) then
        M.executables[#M.executables + 1] = path
        M.last_chosen = #M.executables
    else
        vim.notify(string.format("Path %s already registered", path), 1)
    end
    return path
end

local input = async.wrap(vim.ui.input, 2)

function M.get_gtest_executable(root)
    if #M.executables ~= 0 then
        local options = {}
        options[1] = "Choose the executable (or enter a new path)\n"
        for i, pth in ipairs(M.executables) do
            options[#options + 1] = string.format("%d. %s\n", i, pth)
        end
        options[#options + 1] =
            "Enter the number of the executable (q or empty cancels): "
        local prompt = table.concat(options, "")
        local inpt = input({
            prompt = prompt,
            default = M.last_chosen and tostring(M.last_chosen) or "",
            completion = "file",
            cancelreturn = ""
        })
        if inpt == "q" or inpt == "" then return nil end
        local chosen = tonumber(inpt)
        if chosen == nil then
            return add_gtest_executable(inpt, root)
        elseif chosen > #M.executables or chosen < 1 then
            vim.notify(inpt .. " is out of range")
            return nil
        else
            M.last_chosen = chosen
            return M.executables[chosen]
        end
    else
        local prompt = "Enter gtest executable path (q or empty cancels): "
        local inpt = input({
            prompt = prompt,
            default = "",
            completion = "file",
            cancelreturn = ""
        })
        if inpt == "q" or inpt == "" or inpt == "nil" then return nil end
        return add_gtest_executable(inpt, root)
    end
end

local function get_candidates()
    local candidates
    if vim.fn.has("win32") == 1 then
        candidates = {
            vim.env.TMPDIR or "", vim.env.TMP or "", vim.env.TEMP or "",
            vim.env.USERPROFILE, vim.fn.getcwd()
        }
    else
        candidates = {
            vim.env.TMPDIR or "", "/tmp", vim.fn.getcwd(), vim.env.HOME
        }

    end
    return candidates
end

local function symlink(path, new_path)
    if vim.fn.has("win32") == 0 then
        vim.fn.delete(new_path)
        vim.loop.fs_symlink(path, new_path)
    end
    -- otherwise just don't bother
end

-- follows tmpdir convention similar to pytest
-- Keeps opts.history_size directories present at the same time, deleting any
-- extra directories.
function M.test_results_dir(opts)
    opts = opts or {}
    opts.history_size = opts.history_size or 3
    local parent_path
    if opts.parent_path then
        parent_path = nil
    else
        for _, dir in ipairs(get_candidates()) do
            if #dir ~= 0 then
                parent_path = Path:new(dir, string.format("googletest-of-%s",
                                                          vim.env.USER))
                parent_path:mkdir({exist_ok = true})
                break
            end
        end
    end

    local existing_paths = {}
    for _, dir in ipairs(scandir.scan_dir(parent_path.filename,
                                          {depth = 1, only_dirs = true})) do
        if dir:match("%/neotest%-gtest%-run%-%d+$") then
            existing_paths[#existing_paths + 1] = dir
        end
    end

    -- sort newest -> oldest, only leave history_size - 1 files left
    local path2nr = function(p)
        return tonumber(vim.fn.matchstr(p, [[\d\+$]]))
    end
    table.sort(existing_paths, function(l, r) return path2nr(l) > path2nr(r) end)
    for i = opts.history_size, #existing_paths do
        -- making sure we don't remove something important
        assert(existing_paths[i]:match(
            "%/googletest%-of.*%/neotest%-gtest%-run%-%d+$"))
        vim.fn.delete(existing_paths[i], "rf")
    end

    local new_nr
    if #existing_paths == 0 then
        new_nr = 1
    else
        new_nr = path2nr(existing_paths[1]) + 1
    end
    local new_path = Path:new(parent_path,
                              ("neotest-gtest-run-%d"):format(new_nr))
    new_path:mkdir({exist_ok = false})
    symlink(new_path.filename,
            Path:new(parent_path, "neotest-gtest-latest").filename)
    return new_path.filename
end

return M
