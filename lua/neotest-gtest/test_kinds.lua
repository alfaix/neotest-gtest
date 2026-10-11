local M = {}

local generated = {
  TEST_P = true,
  TYPED_TEST = true,
  TYPED_TEST_P = true,
}

function M.is_generated(kind)
  return generated[kind] == true
end

return M
