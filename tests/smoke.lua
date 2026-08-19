local familiar = require("familiar")
local avatar_mod = require("familiar.avatar")
local config_mod = require("familiar.config")
local easing = require("familiar.easing")
local motion = require("familiar.motion")
local renderer = require("familiar.renderer")
local runtime = require("familiar.runtime")

local config = config_mod.resolve({})
assert(config.skin == "mote")
assert(config.animation.fps == 60)
assert(config.animation.duration_ms == 250)
assert(config.animation.easing == "cubic")
assert(config.animation.trail.mode == "auto")
assert(config.animation.stickiness.enabled == true)

local high_refresh = config_mod.resolve({ animation = { profile = "high_refresh" } })
assert(high_refresh.animation.fps == 120)
assert(high_refresh.animation.duration_ms == 250)
local economy = config_mod.resolve({ animation = { profile = "economy" } })
assert(economy.animation.fps == 30)
assert(config_mod.resolve({ avatar = "fox" }).skin == "fox")

assert(easing.apply("linear", 0.5) == 0.5)
assert(easing.apply("cubic", 0.5) > easing.apply("quad", 0.5))
assert(easing.apply("quart", 0.5) > easing.apply("cubic", 0.5))

local plan = motion.begin({ x = 0, y = 0 }, { x = 20, y = 10 }, 1000, 250, "run", "cubic")
local halfway, done = motion.sample(plan, 1125)
assert(not done)
assert(halfway.x > 10)
assert(halfway.y > 5)
local finish, complete = motion.sample(plan, 1250)
assert(complete and finish.x == 20 and finish.y == 10)
local extended = motion.retarget(plan, finish, { x = 2, y = 2 }, 1240, {
  retarget_min_remaining_ms = 70,
  retarget_max_extend_ms = 80,
})
assert(extended > 0)

local move_ok = motion.should_move({
  semantic_value = 0.2,
  distance = 3,
  since_last_move_ms = 100,
  in_motion = false,
  mode_bias = 0,
  movement = "allow",
  current_safe = true,
}, config.animation.stickiness)
assert(move_ok == false)

local function validate_glyph_skin(skin)
  assert(skin.kind == "glyph")
  assert(skin.height <= 3)
  assert(renderer._render_height(skin) == skin.height)
  for frame_name, _ in pairs(skin.frames) do
    local lines, spans = renderer._frame_lines(skin, frame_name)
    assert(#lines == skin.height)
    assert(#spans == skin.height)
    for row, line in ipairs(lines) do
      assert(vim.fn.strdisplaywidth(line) == skin.width)
      for _, span in ipairs(spans[row]) do
        assert(span[1] < span[2])
        assert(type(span[3]) == "string")
      end
    end
  end
end

local mote = avatar_mod.load("mote")
assert(mote.width == 14)
assert(mote.frames.idle)
assert(mote.poses.focus == "focus")
assert(mote.animations.wave)
assert(mote.animations.peek)
assert(mote.animations.blink.steps[1].duration_ms == 70)
assert(mote.motion.run[1] == "run_1")
validate_glyph_skin(mote)

local spirit = avatar_mod.load("spirit")
assert(spirit.id == "spirit")
assert(spirit.width == 14)
assert(spirit.poses.visual == "visual")
assert(spirit.motion.dash[1] == "dash_1")
assert(spirit.animations.ear_twitch)
validate_glyph_skin(spirit)

local names = avatar_mod.names()
assert(vim.tbl_contains(names, "mote"))
assert(vim.tbl_contains(names, "spirit"))
assert(vim.tbl_contains(names, "fox"))

local bad_role = vim.deepcopy(mote)
bad_role.frames.idle.rows[1][2].role = "missing"
assert(not pcall(avatar_mod.validate, bad_role))

local too_tall = vim.deepcopy(mote)
too_tall.height = 4
assert(not pcall(avatar_mod.validate, too_tall))

local too_wide = vim.deepcopy(mote)
too_wide.frames.idle.rows[1][2].text = "this-is-much-too-wide"
assert(not pcall(avatar_mod.validate, too_wide))

local bad_animation = vim.deepcopy(mote)
bad_animation.animations.idle.steps[1].frame = "missing_frame"
assert(not pcall(avatar_mod.validate, bad_animation))

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

assert(runtime._mode_family("n") == "normal")
assert(runtime._mode_family("i") == "insert")
assert(runtime._mode_family("v") == "visual")
assert(runtime._mode_family("V") == "visual")
assert(runtime._mode_family("no") == "operator")
assert(runtime._mode_family("R") == "replace")
assert(runtime._mode_family("c") == "command")

familiar.setup({ enabled = false, core = { enabled = false } })
assert(familiar.status().running == false)
assert(vim.fn.exists(":FamiliarDemo") == 2)
assert(vim.fn.exists(":FamiliarSkin") == 2)
assert(familiar.skin("spirit") == "spirit")
assert(familiar.skin() == "spirit")
print("familiar.nvim smoke: ok")
