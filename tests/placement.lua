local avatar_mod = require("familiar.avatar")
local config_mod = require("familiar.config")
local renderer = require("familiar.renderer")
local runtime = require("familiar.runtime")
local telemetry = require("familiar.telemetry")
local ui_safety = require("familiar.ui_safety")

local win = vim.api.nvim_get_current_win()
local original_buf = vim.api.nvim_win_get_buf(win)
local buf = vim.api.nvim_create_buf(false, true)
vim.bo[buf].buftype = ""
vim.api.nvim_win_set_buf(win, buf)
vim.wo[win].number = false
vim.wo[win].relativenumber = false
vim.wo[win].signcolumn = "no"
vim.wo[win].foldcolumn = "0"
vim.wo[win].wrap = false

local lines = {}
for _ = 1, 16 do lines[#lines + 1] = "short" end
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.api.nvim_win_set_cursor(win, { 1, 0 })
vim.cmd("redraw")

local avatar = avatar_mod.load("mote")
local opts = {
  margin = 1,
  min_width = 1,
  min_height = 1,
  max_candidates = 20,
}
local width = vim.api.nvim_win_get_width(win)
local x = width - avatar.width - opts.margin

local ns = vim.api.nvim_create_namespace("FamiliarPlacementTest")
vim.api.nvim_buf_set_extmark(buf, ns, 1, 5, {
  virt_text = { { "diagnostic", "ErrorMsg" } },
  virt_text_pos = "right_align",
})
vim.cmd("redraw")
assert(renderer._right_edges(win)[1] == width - 1)
assert(renderer.is_safe_position(win, avatar, opts, { x = x, y = 1 }) == false)
vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

vim.api.nvim_buf_set_extmark(buf, ns, 1, 5, {
  virt_text = { { string.rep("v", width), "Comment" } },
  virt_text_pos = "eol",
})
vim.cmd("redraw")
assert(renderer._right_edges(win)[1] == width - 1)
assert(renderer.is_safe_position(win, avatar, opts, { x = x, y = 1 }) == false)
vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

vim.wo[win].wrap = true
lines[2] = string.rep("w", width * 2)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.cmd("redraw")
assert(renderer._right_edges(win)[1] == width - 1)
assert(renderer.is_safe_position(win, avatar, opts, { x = x, y = 1 }) == false)
vim.wo[win].wrap = false
lines[2] = "short"

lines[5] = string.rep("x", width - 2)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.cmd("redraw")

local from = { x = x, y = 1 }
local target = { x = x, y = 7 }
assert(renderer.is_safe_position(win, avatar, opts, from) == true)
assert(renderer.is_safe_position(win, avatar, opts, target) == true)
assert(renderer.is_safe_path(win, avatar, opts, from, target) == false)

local guard_before = renderer.stats().safety_suppressed
assert(renderer.draw(win, avatar, "idle", { x = x, y = 4 }) == false)
assert(renderer.stats().safety_suppressed == guard_before + 1)
assert(renderer.draw(win, avatar, "idle", target) == true)
renderer.hide()

local safe_trail = renderer._filter_safe_points(win, {
  { x = x, y = 4, glyph = "x" },
  { x = x, y = 10, glyph = "x" },
}, opts)
assert(#safe_trail == 1)
assert(safe_trail[1].y == 10)

for _, candidate in ipairs(renderer.find_safe_positions(win, avatar, opts)) do
  assert(renderer.is_safe_position(win, avatar, opts, candidate))
end

local text_changed_count = 0
local saw_ui_changed = false
telemetry.setup(config_mod.resolve({ enabled = false }), function(kind, args)
  if kind == "text_changed" then
    text_changed_count = text_changed_count + 1
    if args and args.event == "FamiliarUiChanged" then saw_ui_changed = true end
  end
end)
vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
assert(text_changed_count >= 1)

vim.cmd("redraw")
assert(vim.wait(500, function() return ui_safety._tracked_signature(win) ~= nil end))
local baseline_ui_signature = ui_safety._tracked_signature(win)
vim.api.nvim_buf_set_extmark(buf, ns, 2, 1, {
  virt_text = { { "dynamic-overlay", "Comment" } },
  virt_text_pos = "right_align",
})
vim.cmd("redraw")
assert(vim.wait(1000, function() return saw_ui_changed end))
assert(ui_safety._tracked_signature(win) ~= baseline_ui_signature)
vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
telemetry.stop()

for index = 1, #lines do lines[index] = "short" end
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.cmd("redraw")
local runtime_config = config_mod.resolve({
  core = { enabled = false },
  brain = { enabled = false },
})
runtime.start(runtime_config)
local before = assert(runtime.status().position)
local occupied = math.floor(before.y + 0.5) + 1
for index = occupied, occupied + renderer._render_height(avatar) - 1 do
  lines[index] = string.rep("x", width - 2)
end
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
local after = assert(runtime.status().position)
assert(after.x ~= before.x or after.y ~= before.y)
assert(renderer.is_safe_position(win, avatar, runtime_config.render, after))
runtime.stop()

vim.api.nvim_win_set_buf(win, original_buf)
vim.api.nvim_buf_delete(buf, { force = true })
print("familiar.nvim placement safety: ok")
