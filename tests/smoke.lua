local familiar = require("familiar")
local avatar_mod = require("familiar.avatar")
local renderer = require("familiar.renderer")

local mote = avatar_mod.load("mote")
assert(mote.kind == "glyph")
assert(mote.width == 12)
assert(mote.height == 3)
assert(renderer._render_height(mote) == 3)
assert(mote.frames.idle_1)
assert(mote.animations.wave)
assert(mote.animations.peek)

for frame_name, _ in pairs(mote.frames) do
  local lines, spans = renderer._frame_lines(mote, frame_name)
  assert(#lines == mote.height)
  assert(#spans == mote.height)

  for row, line in ipairs(lines) do
    assert(vim.fn.strdisplaywidth(line) == mote.width)
    for _, span in ipairs(spans[row]) do
      assert(span[1] < span[2])
      assert(type(span[3]) == "string")
    end
  end
end

local bad_role = vim.deepcopy(mote)
bad_role.frames.idle_1.rows[1][2].role = "missing"
assert(not pcall(avatar_mod.validate, bad_role))

local too_tall = vim.deepcopy(mote)
too_tall.height = 4
assert(not pcall(avatar_mod.validate, too_tall))

local too_wide = vim.deepcopy(mote)
too_wide.frames.idle_1.rows[1][2].text = "this-is-much-too-wide"
assert(not pcall(avatar_mod.validate, too_wide))

-- Keep the existing half-block fox valid as an alternate renderer while the
-- new glyph actor becomes the default.
local fox = avatar_mod.load("fox")
assert(avatar_mod.kind(fox) == "pixel")
assert(fox.width == 16)
assert(fox.height == 16)
assert(renderer._render_height(fox) == 8)
assert(fox.frames.idle_1)

for frame_name, _ in pairs(fox.frames) do
  local lines, spans = renderer._frame_lines(fox, frame_name)
  assert(#lines == fox.height / 2)
  assert(#spans == fox.height / 2)

  local span_count = 0
  for row, line in ipairs(lines) do
    assert(vim.fn.strdisplaywidth(line) == fox.width)
    for _, span in ipairs(spans[row]) do
      assert(span[1] < span[2])
      assert(type(span[3]) == "string")
      span_count = span_count + 1
    end
  end

  assert(span_count < fox.width * (fox.height / 2))
end

local bad_palette = vim.deepcopy(fox)
bad_palette.frames.idle_1[1] = "Z" .. bad_palette.frames.idle_1[1]:sub(2)
assert(not pcall(avatar_mod.validate, bad_palette))

local bad_animation = vim.deepcopy(mote)
bad_animation.animations.idle.frames[1] = "missing_frame"
assert(not pcall(avatar_mod.validate, bad_animation))

familiar.setup({ enabled = false, core = { enabled = false } })
assert(familiar.status().running == false)
assert(vim.fn.exists(":FamiliarDemo") == 2)
print("familiar.nvim smoke: ok")
