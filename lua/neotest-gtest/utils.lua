local Path = require("plenary.path")
local M = {}

M.test_extensions = {
    ["cpp"] = true,
    ["cc"] = true,
    ["cxx"] = true,
    ["c++"] = true
}

function M.fexists(path)
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

-- used to make sure the same file is represented by identical strings
function M.normalize_path(path)
    if path[1] == '~' and (path[2] == Path.path.sep or #path == 1) then
        path = vim.loop.os_getenv("HOME") .. path:sub(2)
    end
    return Path:new(path):absolute()
end

function M.encode_path(path)
    path = M.normalize_path(path)
    -- there are never two slashes in a row: path is normalized. Replace slash
    local encoded = path:gsub("%%", "%%1")
    encoded = encoded:gsub("%" .. Path.path.sep, "%%0")
    return encoded
end

function M.decode_path(encoded_path)
    encoded_path = encoded_path:gsub("%%0", Path.path.sep)
    encoded_path = encoded_path:gsub("%%1", "%%")
    return encoded_path
end

return M
