local M = {}

local builtins = {
  fox = "familiar.avatars.fox",
}

local function validate(avatar)
  assert(type(avatar) == "table", "familiar avatar must be a table")
  assert(type(avatar.id) == "string", "familiar avatar.id is required")
  assert(type(avatar.width) == "number" and avatar.width > 0, "familiar avatar.width must be positive")
  assert(type(avatar.height) == "number" and avatar.height > 0, "familiar avatar.height must be positive")
  assert(avatar.height % 2 == 0, "familiar avatar.height must be even for half-block rendering")
  assert(type(avatar.palette) == "table", "familiar avatar.palette is required")
  assert(type(avatar.frames) == "table", "familiar avatar.frames is required")
  assert(type(avatar.animations) == "table", "familiar avatar.animations is required")

  for name, frame in pairs(avatar.frames) do
    assert(#frame == avatar.height, ("frame %s has wrong height"):format(name))
    for row, pixels in ipairs(frame) do
      assert(#pixels == avatar.width, ("frame %s row %d has wrong width"):format(name, row))
    end
  end

  return avatar
end

function M.load(name)
  local module = builtins[name]
  if not module then
    error(("unknown familiar avatar: %s"):format(tostring(name)))
  end
  return validate(require(module))
end

return M
