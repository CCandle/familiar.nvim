local familiar = require("familiar")
local avatar_mod = require("familiar.avatar")
local avatar = avatar_mod.load("fox")
local renderer = require("familiar.renderer")

assert(avatar.width == 16)
assert(avatar.height == 16)
assert(avatar.frames.idle_1)

for frame_name, _ in pairs(avatar.frames) do
  local lines, spans = renderer._frame_lines(avatar, frame_name)
  assert(#lines == avatar.height / 2)
  assert(#spans == avatar.height / 2)

  local span_count = 0
  for row, line in ipairs(lines) do
    assert(vim.fn.strdisplaywidth(line) == avatar.width)
    for _, span in ipairs(spans[row]) do
      assert(span[1] < span[2])
      assert(type(span[3]) == "string")
      span_count = span_count + 1
    end
  end

  -- A naive implementation would emit one extmark for every 16x8 cell.
  -- Runs should keep the real draw workload comfortably below that ceiling.
  assert(span_count < avatar.width * (avatar.height / 2))
end

local bad_palette = vim.deepcopy(avatar)
bad_palette.frames.idle_1[1] = "Z" .. bad_palette.frames.idle_1[1]:sub(2)
assert(not pcall(avatar_mod.validate, bad_palette))

local bad_animation = vim.deepcopy(avatar)
bad_animation.animations.idle.frames[1] = "missing_frame"
assert(not pcall(avatar_mod.validate, bad_animation))

familiar.setup({ enabled = false, core = { enabled = false } })
assert(familiar.status().running == false)
assert(vim.fn.exists(":FamiliarDemo") == 2)
print("familiar.nvim smoke: ok")
