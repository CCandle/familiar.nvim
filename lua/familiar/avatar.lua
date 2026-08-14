local M = {}

local builtins = {
  fox = "familiar.avatars.fox",
}

local function fail(message)
  error("familiar avatar: " .. message, 3)
end

local function validate_palette(avatar)
  for key, value in pairs(avatar.palette) do
    if type(key) ~= "string" or #key ~= 1 or key == "." then
      fail("palette keys must be single ASCII characters other than '.'")
    end
    if type(value) ~= "string" or value == "" then
      fail(("palette entry %s must be a non-empty color string"):format(tostring(key)))
    end
  end
end

local function validate_frames(avatar)
  for name, frame in pairs(avatar.frames) do
    if type(name) ~= "string" or type(frame) ~= "table" then
      fail("frame names must map to row tables")
    end
    if #frame ~= avatar.height then
      fail(("frame %s has height %d, expected %d"):format(name, #frame, avatar.height))
    end

    for row, pixels in ipairs(frame) do
      if type(pixels) ~= "string" or #pixels ~= avatar.width then
        fail(("frame %s row %d has wrong width"):format(name, row))
      end
      for column = 1, #pixels do
        local pixel = pixels:sub(column, column)
        if pixel ~= "." and avatar.palette[pixel] == nil then
          fail(("frame %s row %d column %d references unknown palette key %q"):format(name, row, column, pixel))
        end
      end
    end
  end
end

local function validate_animations(avatar)
  for name, animation in pairs(avatar.animations) do
    if type(name) ~= "string" or type(animation) ~= "table" then
      fail("animation names must map to tables")
    end
    if type(animation.frames) ~= "table" or #animation.frames == 0 then
      fail(("animation %s must contain at least one frame"):format(name))
    end
    for index, frame_name in ipairs(animation.frames) do
      if type(frame_name) ~= "string" or avatar.frames[frame_name] == nil then
        fail(("animation %s frame %d references unknown frame %q"):format(name, index, tostring(frame_name)))
      end
    end
    if animation.loop ~= nil and type(animation.loop) ~= "boolean" then
      fail(("animation %s loop must be boolean"):format(name))
    end
    if animation.next ~= nil and avatar.animations[animation.next] == nil then
      fail(("animation %s next references unknown animation %q"):format(name, tostring(animation.next)))
    end
  end
end

function M.validate(avatar)
  if type(avatar) ~= "table" then fail("package must be a table") end
  if type(avatar.id) ~= "string" or avatar.id == "" then fail("id is required") end
  if type(avatar.width) ~= "number" or avatar.width <= 0 or avatar.width % 1 ~= 0 then
    fail("width must be a positive integer")
  end
  if type(avatar.height) ~= "number" or avatar.height <= 0 or avatar.height % 1 ~= 0 then
    fail("height must be a positive integer")
  end
  if avatar.height % 2 ~= 0 then fail("height must be even for half-block rendering") end
  if type(avatar.palette) ~= "table" then fail("palette is required") end
  if type(avatar.frames) ~= "table" then fail("frames are required") end
  if type(avatar.animations) ~= "table" then fail("animations are required") end

  validate_palette(avatar)
  validate_frames(avatar)
  validate_animations(avatar)
  return avatar
end

function M.load(name)
  local module = builtins[name]
  if not module then
    error(("unknown familiar avatar: %s"):format(tostring(name)))
  end
  return M.validate(require(module))
end

return M
