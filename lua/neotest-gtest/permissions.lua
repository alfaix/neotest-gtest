local permissions_table = {
	-- user r/w/x
	tonumber("00400", 8),
	tonumber("00200", 8),
	tonumber("00100", 8),
	-- group r/w/x
	tonumber("00040", 8),
	tonumber("00020", 8),
	tonumber("00010", 8),
	-- others r/w/x
	tonumber("00004", 8),
	tonumber("00002", 8),
	tonumber("00001", 8),
}

local function permissions(str)
	assert(#str == #permissions_table, "mode string mut have 9 chars, e.g. rw-rwxrwx")
	local mode = 0
	for i = 1, #str do
		if str[i] ~= "-" then
			mode = bit.bor(mode, permissions_table[i])
		end
	end
	return mode
end

return permissions
