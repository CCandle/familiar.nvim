local M = {}

local builtins = {
  mote = "familiar.avatars.mote",
  spirit = "familiar.avatars.spirit",
  fox = "familiar.avatars.fox",
}

local function fail(message)
  error("familiar avatar: " .. message, 3)
end

local function kind_of(avatar)
  return avatar.kind or "pixel"
end

local function validate_colors(palette)
  for key, value in pairs(palette) do
    if type(key) ~= "string" or key == "" then
      fail("palette keys must be non-empty strings")
    end
    if type(value) ~= "string" or value == "" then
      fail(("palette entry %s must be a non-empty color string"):format(tostring(key)))
    end
  end
end

local function validate_pixel_palette(avatar)
  for key, _ in pairs(avatar.palette) do
    if #key ~= 1 or key == "." then
      fail("pixel palette keys must be single ASCII characters other than '.'")
    end
  end
end

local function validate_pixel_frames(avatar)
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

local function validate_glyph_frames(avatar)
  for name, frame in pairs(avatar.frames) do
    if type(name) ~= "string" or type(frame) ~= "table" or type(frame.rows) ~= "table" then
      fail("glyph frame names must map to tables with rows")
    end
    if #frame.rows == 0 or #frame.rows > avatar.height then
      fail(("glyph frame %s must contain 1..%d rows"):format(name, avatar.height))
    end

    for row_index, row in ipairs(frame.rows) do
      if type(row) ~= "table" then
        fail(("glyph frame %s row %d must be a segment table"):format(name, row_index))
      end

      local text = {}
      for segment_index, segment in ipairs(row) do
        if type(segment) ~= "table" or type(segment.text) ~= "string" or segment.text == "" then
          fail(("glyph frame %s row %d segment %d must contain non-empty text"):format(name, row_index, segment_index))
        end
        if segment.text:find("\n", 1, true) then
          fail(("glyph frame %s row %d segment %d contains a newline"):format(name, row_index, segment_index))
        end
        if segment.role ~= nil and avatar.palette[segment.role] == nil then
          fail(("glyph frame %s row %d segment %d references unknown role %q"):format(
            name,
            row_index,
            segment_index,
            tostring(segment.role)
          ))
        end
        text[#text + 1] = segment.text
      end

      local width = vim.fn.strdisplaywidth(table.concat(text))
      if width > avatar.width then
        fail(("glyph frame %s row %d has display width %d, expected <= %d"):format(
          name,
          row_index,
          width,
          avatar.width
        ))
      end
    end
  end
end

local function validate_duration(value, label)
  if type(value) == "number" then
    if value <= 0 then fail(label .. " must be positive") end
    return
  end
  if type(value) == "table" and #value == 2 then
    if type(value[1]) ~= "number" or type(value[2]) ~= "number" or value[1] <= 0 or value[2] < value[1] then
      fail(label .. " range must be {positive_min, max>=min}")
    end
    return
  end
  fail(label .. " must be a positive number or {min, max}")
end

local function validate_animations(avatar)
  for name, animation in pairs(avatar.animations) do
    if type(name) ~= "string" or type(animation) ~= "table" then
      fail("animation names must map to tables")
    end

    local has_frames = type(animation.frames) == "table" and #animation.frames > 0
    local has_steps = type(animation.steps) == "table" and #animation.steps > 0
    if not has_frames and not has_steps then
      fail(("animation %s must contain frames or steps"):format(name))
    end

    if has_frames then
      for index, frame_name in ipairs(animation.frames) do
        if type(frame_name) ~= "string" or avatar.frames[frame_name] == nil then
          fail(("animation %s frame %d references unknown frame %q"):format(name, index, tostring(frame_name)))
        end
      end
      if animation.frame_ms ~= nil then
        validate_duration(animation.frame_ms, ("animation %s frame_ms"):format(name))
      end
    end

    if has_steps then
      for index, step in ipairs(animation.steps) do
        if type(step) ~= "table" or type(step.frame) ~= "string" or avatar.frames[step.frame] == nil then
          fail(("animation %s step %d references an unknown frame"):format(name, index))
        end
        validate_duration(step.duration_ms, ("animation %s step %d duration_ms"):format(name, index))
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

local function validate_poses(avatar)
  if avatar.poses == nil then return end
  if type(avatar.poses) ~= "table" then fail("poses must be a table") end
  for name, frame in pairs(avatar.poses) do
    if type(name) ~= "string" or type(frame) ~= "string" or avatar.frames[frame] == nil then
      fail(("pose %q references unknown frame %q"):format(tostring(name), tostring(frame)))
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
  if type(avatar.palette) ~= "table" then fail("palette is required") end
  if type(avatar.frames) ~= "table" then fail("frames are required") end
  if type(avatar.animations) ~= "table" then fail("animations are required") end

  local kind = kind_of(avatar)
  if kind ~= "pixel" and kind ~= "glyph" then
    fail(("unsupported renderer kind %q"):format(tostring(kind)))
  end

  validate_colors(avatar.palette)
  if kind == "pixel" then
    if avatar.height % 2 ~= 0 then fail("pixel height must be even for half-block rendering") end
    validate_pixel_palette(avatar)
    validate_pixel_frames(avatar)
  else
    if avatar.height > 3 then fail("glyph avatars are limited to at most 3 terminal rows") end
    validate_glyph_frames(avatar)
  end

  validate_poses(avatar)
  validate_animations(avatar)
  return avatar
end

function M.kind(avatar)
  return kind_of(avatar)
end

function M.render_height(avatar)
  if kind_of(avatar) == "pixel" then
    return avatar.height / 2
  end
  return avatar.height
end

function M.names()
  local names = vim.tbl_keys(builtins)
  table.sort(names)
  return names
end

function M.load(name)
  local module = builtins[name]
  if not module then
    error(("unknown familiar skin: %s"):format(tostring(name)))
  end
  return M.validate(require(module))
end

return M
