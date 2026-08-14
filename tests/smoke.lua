local familiar = require("familiar")
local avatar = require("familiar.avatar").load("fox")
local renderer = require("familiar.renderer")

assert(avatar.width == 16)
assert(avatar.height == 16)
assert(avatar.frames.idle_1)

local lines, spans = renderer._frame_lines(avatar, "idle_1")
assert(#lines == 8)
assert(#spans == 8)
for _, line in ipairs(lines) do
  assert(vim.fn.strdisplaywidth(line) == 16)
end

familiar.setup({ enabled = false, core = { enabled = false } })
assert(familiar.status().running == false)
print("familiar.nvim smoke: ok")
