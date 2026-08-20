local avatar_loader = require("familiar.avatar")
local client = require("familiar.client")
local motion = require("familiar.motion")
local renderer = require("familiar.renderer")
local telemetry = require("familiar.telemetry")

local M = {}
local uv = vim.uv or vim.loop

local state = {
  running = false,
  config = nil,
  avatar = nil,
  parent = nil,
  buffer = nil,

  snapshot_timer = nil,
  active_timer = nil,
  active_interval_ms = nil,

  position = nil,
  target = nil,
  motion = nil,
  last_motion_end_ms = -math.huge,
  last_recompute_ms = 0,
  last_trail_sample_ms = 0,
  trail_samples = {},

  base_behavior = "idle",
  base_frame = nil,
  sequence = nil,
  sequence_token = 0,
  transition = nil,
  demo = nil,

  intent = nil,
  mode_family = "normal",
  last_mode_reaction_ms = -math.huge,
  last_typing_ms = -math.huge,
  last_save_reaction_ms = -math.huge,
  last_diagnostic_reaction_ms = -math.huge,
  last_errors = 0,

  blink_token = 0,
  ambient_token = 0,

  seq = 0,
  last_snapshot_ms = 0,
  stats = {
    motions = 0,
    retargets = 0,
    suppressed_moves = 0,
    deadline_extensions = 0,
    warps = 0,
  },
}

local function now_ms()
  return uv.hrtime() / 1e6
end

local function wall_ms()
  return uv.now()
end

local function debug_log(message)
  if state.config and state.config.debug then
    vim.notify("familiar: " .. message, vim.log.levels.DEBUG)
  end
end

local function normal_parent()
  local win = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then return nil end
  local cfg = vim.api.nvim_win_get_config(win)
  if cfg.relative and cfg.relative ~= "" then return nil end
  local buf = vim.api.nvim_win_get_buf(win)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return nil end
  return win, buf
end

local function mode_family(mode)
  mode = mode or vim.api.nvim_get_mode().mode
  if mode:sub(1, 2) == "no" then return "operator" end
  local first = mode:sub(1, 1)
  if first == "i" then return "insert" end
  if first == "R" then return "replace" end
  if first == "c" then return "command" end
  if first == "t" then return "terminal" end
  if first == "v" or mode == "V" or mode == "\22" or first == "s" or mode == "S" or mode == "\19" then
    return "visual"
  end
  if first == "r" or first == "!" then return "prompt" end
  return "normal"
end

local function mode_policy(family)
  return state.config.interaction.modes[family] or state.config.interaction.modes.normal
end

local function frame_for_behavior(behavior)
  if state.avatar.poses and state.avatar.poses[behavior] then
    return state.avatar.poses[behavior]
  end
  local animation = state.avatar.animations[behavior]
  if animation then
    if animation.steps and animation.steps[1] then return animation.steps[1].frame end
    if animation.frames and animation.frames[1] then return animation.frames[1] end
  end
  if state.avatar.poses and state.avatar.poses.idle then return state.avatar.poses.idle end
  local idle = state.avatar.animations.idle
  if idle then
    if idle.steps and idle.steps[1] then return idle.steps[1].frame end
    if idle.frames and idle.frames[1] then return idle.frames[1] end
  end
  return next(state.avatar.frames)
end

local function motion_frame_names(kind)
  local frames = state.avatar.motion and state.avatar.motion[kind]
  if frames and #frames > 0 then return frames end

  local animation = state.avatar.animations[kind]
  if animation then
    if animation.frames and #animation.frames > 0 then return animation.frames end
    if animation.steps and #animation.steps > 0 then
      local names = {}
      for _, step in ipairs(animation.steps) do
        names[#names + 1] = step.frame
      end
      return names
    end
  end

  return nil
end

local function current_frame(t)
  if state.motion then
    local motion_frames = motion_frame_names(state.motion.kind)
    if motion_frames and #motion_frames > 0 then
      local pose_ms = state.config.animation.expression.motion_pose_ms
      local elapsed = t - state.motion.started_ms
      return motion_frames[(math.floor(elapsed / pose_ms) % #motion_frames) + 1]
    end
  end
  if state.sequence and state.sequence.frame then return state.sequence.frame end
  return state.base_frame or frame_for_behavior("idle")
end

local function render_now(t)
  if not state.position or not state.parent or not vim.api.nvim_win_is_valid(state.parent) then
    renderer.hide()
    return
  end
  renderer.draw(state.parent, state.avatar, current_frame(t or now_ms()), state.position)
end

local function set_behavior(behavior)
  state.base_behavior = behavior
  state.base_frame = frame_for_behavior(behavior)
  if not state.motion and not state.sequence then render_now() end
end

local function duration_value(value)
  if type(value) == "table" then
    local lo, hi = value[1], value[2]
    if hi <= lo then return lo end
    return math.random(lo, hi)
  end
  return value
end

local function animation_steps(animation)
  if animation.steps and #animation.steps > 0 then return animation.steps end
  local result = {}
  local duration = duration_value(animation.frame_ms or 125)
  for _, frame in ipairs(animation.frames or {}) do
    result[#result + 1] = { frame = frame, duration_ms = duration }
  end
  return result
end

local function cancel_sequence(force)
  if state.sequence and state.sequence.protected and not force then return false end
  state.sequence_token = state.sequence_token + 1
  state.sequence = nil
  return true
end

local advance_sequence

local function finish_sequence(token)
  if not state.sequence or state.sequence.token ~= token then return end
  local seq = state.sequence
  state.sequence = nil
  if seq.on_done then seq.on_done() end
  if not state.sequence and not state.motion then render_now() end
end

advance_sequence = function(token)
  if not state.running or not state.sequence or state.sequence.token ~= token then return end
  local seq = state.sequence
  local animation = state.avatar.animations[seq.name]
  if not animation then
    finish_sequence(token)
    return
  end

  if seq.until_ms and now_ms() >= seq.until_ms then
    finish_sequence(token)
    return
  end

  local steps = animation_steps(animation)
  if #steps == 0 then
    finish_sequence(token)
    return
  end

  if seq.index > #steps then
    if seq.loop or animation.loop then
      seq.index = 1
    else
      finish_sequence(token)
      return
    end
  end

  local step = steps[seq.index]
  seq.frame = step.frame
  seq.index = seq.index + 1
  render_now()

  local delay = math.max(1, duration_value(step.duration_ms))
  vim.defer_fn(function()
    advance_sequence(token)
  end, delay)
end

local function play_sequence(name, opts)
  opts = opts or {}
  if not state.avatar.animations[name] then return false end
  if state.sequence and state.sequence.protected and not opts.force then return false end

  cancel_sequence(true)
  state.sequence_token = state.sequence_token + 1
  local token = state.sequence_token
  state.sequence = {
    token = token,
    name = name,
    index = 1,
    frame = nil,
    loop = opts.loop == true,
    until_ms = opts.until_ms,
    protected = opts.protected == true,
    on_done = opts.on_done,
  }
  advance_sequence(token)
  return true
end

local function update_trail(t)
  local visible = {}
  local lifetime = state.config.animation.trail.lifetime_ms
  local glyphs = { "≡", "⠂", "⠄", "·" }

  local i = 1
  while i <= #state.trail_samples do
    local sample = state.trail_samples[i]
    local age = t - sample.t
    if age >= lifetime then
      table.remove(state.trail_samples, i)
    else
      local level = math.max(1, math.min(4, math.floor((age / lifetime) * 4) + 1))
      visible[#visible + 1] = {
        x = sample.x,
        y = sample.y,
        glyph = level == 1 and sample.glyph or glyphs[level],
        level = level,
      }
      i = i + 1
    end
  end

  if #visible > 0 and state.parent then
    renderer.draw_trail(state.parent, state.avatar, visible, state.config.render)
  else
    renderer.clear_trail()
  end
end

local function trail_enabled_for_plan(plan)
  local opts = state.config.animation.trail
  if opts.mode == "none" then return false end
  if opts.mode == "always" then return true end
  return plan.distance >= opts.min_distance and (plan.kind == "run" or plan.kind == "dash")
end

local function sample_trail(t, previous)
  if not state.motion or not trail_enabled_for_plan(state.motion) then return end
  local opts = state.config.animation.trail
  if t - state.last_trail_sample_ms < opts.sample_ms then return end
  state.last_trail_sample_ms = t

  local dx = state.motion.target.x - state.motion.from.x
  local dy = state.motion.target.y - state.motion.from.y
  local height = avatar_loader.render_height(state.avatar)
  local x, y, glyph

  if math.abs(dx) >= math.abs(dy) then
    x = dx >= 0 and (previous.x - 1) or (previous.x + state.avatar.width)
    y = previous.y + height - 1
    glyph = "≡"
  else
    x = previous.x + math.floor(state.avatar.width / 2)
    y = dy >= 0 and (previous.y - 1) or (previous.y + height)
    glyph = "⋮"
  end

  state.trail_samples[#state.trail_samples + 1] = { x = x, y = y, t = t, glyph = glyph }
  while #state.trail_samples > opts.max_samples do table.remove(state.trail_samples, 1) end
end

local function stop_active_timer()
  if state.active_timer and not state.active_timer:is_closing() then
    state.active_timer:stop()
    state.active_timer:close()
  end
  state.active_timer = nil
  state.active_interval_ms = nil
end

local function apply_intent(intent)
  state.intent = intent or { behavior = "idle" }
  if state.demo or state.transition then return end

  local family = state.mode_family
  if family == "insert" then
    set_behavior("focus")
  elseif family == "visual" then
    set_behavior("visual")
  elseif family == "operator" then
    set_behavior("operator")
  elseif family == "replace" then
    set_behavior("replace")
  elseif family == "command" or family == "prompt" then
    set_behavior("command")
  elseif family == "terminal" then
    set_behavior("terminal")
  else
    set_behavior(state.intent.behavior or "idle")
  end
end

local function finish_motion(t)
  if not state.motion then return end
  state.position = { x = state.motion.target.x, y = state.motion.target.y }
  state.target = { x = state.motion.target.x, y = state.motion.target.y }
  state.last_motion_end_ms = t
  state.motion = nil
  apply_intent(state.intent)
end

local function active_tick()
  if not state.running then
    stop_active_timer()
    return
  end
  local t = now_ms()

  if state.motion then
    local previous = { x = state.position.x, y = state.position.y }
    local position, done = motion.sample(state.motion, t)
    state.position = position
    sample_trail(t, previous)
    render_now(t)
    if done then finish_motion(t) end
  end

  update_trail(t)

  if not state.motion and #state.trail_samples == 0 then
    stop_active_timer()
    render_now(t)
  end
end

local function ensure_active_timer()
  local fps = state.config.animation.fps
  local interval = math.max(1, math.floor(1000 / fps + 0.5))
  if state.active_timer and state.active_interval_ms == interval then return end
  stop_active_timer()
  state.active_interval_ms = interval
  state.active_timer = uv.new_timer()
  state.active_timer:start(0, interval, vim.schedule_wrap(active_tick))
end

local function motion_kind_for_distance(dist)
  local opts = state.config.animation.motion
  if dist >= opts.dash_distance then return "dash" end
  if dist >= opts.run_distance then return "run" end
  return "walk"
end

local function motion_duration(kind)
  local opts = state.config.animation.motion
  if kind == "dash" then return opts.dash_duration_ms end
  return state.config.animation.duration_ms
end

local function finish_transition()
  state.transition = nil
  apply_intent(state.intent)
end

local function warp_to(target, opts)
  opts = opts or {}
  state.stats.warps = state.stats.warps + 1
  state.transition = { kind = "warp", target = target }
  state.motion = nil
  state.trail_samples = {}
  renderer.clear_trail()

  local function arrive()
    state.position = { x = target.x, y = target.y }
    state.target = { x = target.x, y = target.y }
    play_sequence("appear", {
      protected = true,
      force = true,
      on_done = finish_transition,
    })
  end

  if opts.immediate then
    renderer.hide()
    arrive()
    return
  end

  if not play_sequence("vanish", { protected = true, force = true, on_done = arrive }) then arrive() end
end

local function begin_relocation(target, opts)
  opts = opts or {}
  if not target then
    if state.position then
      local current_safe = renderer.is_safe_position(state.parent, state.avatar, state.config.render, state.position)
      if current_safe then
        state.transition = { kind = "hide" }
        play_sequence("vanish", {
          protected = true,
          force = true,
          on_done = function()
            renderer.hide()
            state.position, state.target, state.transition = nil, nil, nil
          end,
        })
      else
        renderer.hide()
        state.position, state.target, state.motion, state.transition = nil, nil, nil, nil
        state.trail_samples = {}
      end
    else
      renderer.hide()
    end
    return
  end

  state.target = { x = target.x, y = target.y }
  if not state.position then
    state.position = { x = target.x, y = target.y }
    state.transition = { kind = "appear" }
    if not play_sequence("appear", { protected = true, force = true, on_done = finish_transition }) then
      finish_transition()
    end
    return
  end

  local dist = motion.distance(state.position, target)
  if dist < 0.5 then return end

  local current_safe = renderer.is_safe_position(state.parent, state.avatar, state.config.render, state.position)
  local policy = mode_policy(state.mode_family)
  local should_move = motion.should_move({
    semantic_value = opts.semantic_value or 0.5,
    distance = dist,
    since_last_move_ms = now_ms() - state.last_motion_end_ms,
    in_motion = state.motion ~= nil,
    mode_bias = policy.utility_bias or 0,
    movement = policy.movement,
    current_safe = current_safe,
    force = opts.force == true or not current_safe,
  }, state.config.animation.stickiness)

  if state.config.animation.stickiness.enabled and not should_move and not opts.force and current_safe then
    state.stats.suppressed_moves = state.stats.suppressed_moves + 1
    state.target = { x = state.position.x, y = state.position.y }
    return
  end

  if not current_safe then
    warp_to(target, { immediate = true })
    return
  end

  if not renderer.is_safe_path(state.parent, state.avatar, state.config.render, state.position, target) then
    warp_to(target)
    return
  end

  if dist >= state.config.render.warp_distance then
    warp_to(target)
    return
  end

  cancel_sequence(false)
  local t = now_ms()
  if state.motion then
    local extended = motion.retarget(state.motion, state.position, target, t, state.config.animation.motion)
    state.motion.kind = motion_kind_for_distance(state.motion.distance)
    if extended > 0 then state.stats.deadline_extensions = state.stats.deadline_extensions + 1 end
    state.stats.retargets = state.stats.retargets + 1
  else
    local kind = motion_kind_for_distance(dist)
    state.motion = motion.begin(
      state.position,
      target,
      t,
      motion_duration(kind),
      kind,
      state.config.animation.easing
    )
    state.stats.motions = state.stats.motions + 1
  end
  state.last_trail_sample_ms = 0
  ensure_active_timer()
end

local function recompute_target(force, reason)
  local parent, buf = normal_parent()
  if not parent then
    begin_relocation(nil)
    state.parent, state.buffer = nil, nil
    return
  end

  local changed_context = state.parent ~= parent or state.buffer ~= buf
  local current_safe
  if not changed_context and state.position then
    current_safe = renderer.is_safe_position(parent, state.avatar, state.config.render, state.position)
    if current_safe and not force then
      if state.motion
        and not renderer.is_safe_path(parent, state.avatar, state.config.render, state.position, state.motion.target)
      then
        state.motion = nil
        state.target = { x = state.position.x, y = state.position.y }
        state.last_motion_end_ms = now_ms()
        state.trail_samples = {}
        renderer.clear_trail()
        apply_intent(state.intent)
      else
        state.target = state.motion and { x = state.motion.target.x, y = state.motion.target.y }
          or { x = state.position.x, y = state.position.y }
      end
      return
    end
  end

  local t = wall_ms()
  local throttle = state.config.render.recompute_throttle_ms or 80
  local safety_urgent = current_safe == false
  if not force and not safety_urgent and t - state.last_recompute_ms < throttle then return end
  state.last_recompute_ms = t

  if changed_context then
    renderer.hide()
    state.position, state.target, state.motion = nil, nil, nil
    state.trail_samples = {}
  end
  state.parent, state.buffer = parent, buf

  local target = renderer.find_safe_position(parent, state.avatar, state.config.render)
  if changed_context then
    begin_relocation(target, { semantic_value = 1.0, force = true })
    return
  end

  local semantic = ({
    winresized = 0.95,
    winscrolled = 0.45,
    diagnosticchanged = 0.75,
    text_changed = 1.00,
    modechanged = 0.35,
    wander = 0.30,
  })[reason] or 0.55
  begin_relocation(target, { semantic_value = semantic, force = force })
end

local function local_intent(snapshot)
  if not snapshot then return { behavior = "idle" } end
  local family = mode_family(snapshot.mode)
  if family == "insert" then return { behavior = "focus", mood = "focused" } end
  if family == "visual" then return { behavior = "visual", mood = "curious" } end
  if family == "operator" then return { behavior = "operator", mood = "focused" } end
  if family == "replace" then return { behavior = "replace", mood = "focused", emote = "alert" } end
  if family == "command" or family == "prompt" then return { behavior = "command", mood = "calm" } end
  if family == "terminal" then return { behavior = "terminal", mood = "calm" } end

  if snapshot.activity.idle_ms >= 120000 then return { behavior = "sleep", mood = "sleepy" } end
  if snapshot.diagnostics.errors > 0 then
    return { behavior = "inspect", mood = "concerned", emote = "question" }
  end
  if snapshot.activity.buffer_switches_10s >= 3 then
    return { behavior = "curious", mood = "curious", emote = "question" }
  end
  if snapshot.activity.typing then return { behavior = "focus", mood = "focused" } end
  return { behavior = "idle", mood = "calm" }
end

local function observe_snapshot(snapshot)
  if not snapshot then return end
  local errors = snapshot.diagnostics.errors or 0
  if state.last_errors > 0 and errors == 0 then
    local t = now_ms()
    local cooldown = state.config.animation.expression.diagnostic_reaction_cooldown_ms
    if state.mode_family == "normal" and t - state.last_diagnostic_reaction_ms >= cooldown then
      state.last_diagnostic_reaction_ms = t
      play_sequence("success")
    end
  end
  state.last_errors = errors
end

local function on_core_message(message)
  if message.type == "ready" then
    debug_log(("core ready: protocol=%s version=%s"):format(tostring(message.protocol), tostring(message.version)))
  elseif message.type == "intent" and message.intent then
    apply_intent(message.intent)
  elseif message.type == "error" then
    debug_log("core error: " .. tostring(message.message))
  end
end

local function send_snapshot(force)
  if not state.running then return end
  local t = wall_ms()
  if not force and t - state.last_snapshot_ms < state.config.telemetry.snapshot_ms then return end
  state.last_snapshot_ms = t

  local snapshot = telemetry.snapshot(state.config)
  if not snapshot then return end
  state.mode_family = mode_family(snapshot.mode)
  observe_snapshot(snapshot)

  if client.running() then
    state.seq = state.seq + 1
    client.send({ type = "snapshot", seq = state.seq, snapshot = snapshot })
  else
    apply_intent(local_intent(snapshot))
  end
end

local function random_delay(min_ms, max_ms)
  if max_ms <= min_ms then return min_ms end
  return math.random(min_ms, max_ms)
end

local function schedule_blink()
  state.blink_token = state.blink_token + 1
  local token = state.blink_token
  local opts = state.config.animation.expression
  vim.defer_fn(function()
    if not state.running or token ~= state.blink_token then return end
    local can_blink = not state.motion and not state.transition and not state.demo and not state.sequence and state.base_behavior ~= "sleep"
    if can_blink then play_sequence("blink") end
    schedule_blink()
  end, random_delay(opts.blink_min_ms, opts.blink_max_ms))
end

local function schedule_ambient()
  state.ambient_token = state.ambient_token + 1
  local token = state.ambient_token
  local opts = state.config.animation.expression
  vim.defer_fn(function()
    if not state.running or token ~= state.ambient_token then return end
    local policy = mode_policy(state.mode_family)
    local quiet = not state.motion and not state.transition and not state.demo and not state.sequence
    if policy.ambient and quiet and state.base_behavior == "idle" and now_ms() - state.last_typing_ms > 1800 then
      local choices = { "glance", "ear_twitch", "glance", "stretch", "curious" }
      play_sequence(choices[math.random(1, #choices)])
    end
    schedule_ambient()
  end, random_delay(opts.ambient_min_ms, opts.ambient_max_ms))
end

local function react_to_mode()
  local t = now_ms()
  if t - state.last_mode_reaction_ms < state.config.interaction.mode_reaction_cooldown_ms then return end
  state.last_mode_reaction_ms = t

  if state.mode_family == "normal" then
    apply_intent(state.intent or { behavior = "idle" })
  elseif state.mode_family == "insert" then
    cancel_sequence(false)
    set_behavior("focus")
  elseif state.mode_family == "visual" then
    cancel_sequence(false)
    set_behavior("visual")
  elseif state.mode_family == "operator" then
    cancel_sequence(false)
    set_behavior("operator")
  elseif state.mode_family == "replace" then
    cancel_sequence(false)
    set_behavior("replace")
  elseif state.mode_family == "command" or state.mode_family == "prompt" then
    cancel_sequence(false)
    set_behavior("command")
  elseif state.mode_family == "terminal" then
    cancel_sequence(false)
    set_behavior("terminal")
  end
end

local function on_editor_event(kind, args)
  if not state.running then return end

  if kind == "typing" then
    state.last_typing_ms = now_ms()
    if state.mode_family == "insert" then set_behavior("focus") end
  elseif kind == "modechanged" then
    state.mode_family = mode_family()
    react_to_mode()
    recompute_target(false, "modechanged")
  elseif kind == "buffer_enter" then
    recompute_target(true, "buffer_enter")
    send_snapshot(true)
  elseif kind == "winresized" then
    recompute_target(false, "winresized")
  elseif kind == "winscrolled" then
    recompute_target(false, "winscrolled")
  elseif kind == "diagnosticchanged" then
    recompute_target(false, "diagnosticchanged")
    send_snapshot(true)
  elseif kind == "text_changed" then
    recompute_target(false, "text_changed")
  elseif kind == "bufwritepost" then
    local t = now_ms()
    local cooldown = state.config.animation.expression.save_reaction_cooldown_ms
    if state.mode_family == "normal" and t - state.last_save_reaction_ms >= cooldown then
      state.last_save_reaction_ms = t
      play_sequence("save")
    end
    send_snapshot(true)
  end

  if client.running() and kind ~= "cursor_moved" and kind ~= "typing" and kind ~= "text_changed" then
    state.seq = state.seq + 1
    client.send({
      type = "event",
      seq = state.seq,
      event = { kind = kind, buffer = args and args.buf or nil },
    })
  end
end

local function start_snapshot_timer()
  if state.snapshot_timer and not state.snapshot_timer:is_closing() then
    state.snapshot_timer:stop()
    state.snapshot_timer:close()
  end
  state.snapshot_timer = uv.new_timer()
  state.snapshot_timer:start(
    state.config.telemetry.snapshot_ms,
    state.config.telemetry.snapshot_ms,
    vim.schedule_wrap(function() send_snapshot(false) end)
  )
end

function M.start(config)
  if state.running then return end
  state.config = config
  state.avatar = avatar_loader.load(config.skin)
  state.running = true
  state.parent, state.buffer = nil, nil
  state.position, state.target, state.motion = nil, nil, nil
  state.trail_samples = {}
  state.transition, state.demo, state.sequence = nil, nil, nil
  state.intent = { behavior = "idle", mood = "calm" }
  state.mode_family = mode_family()
  state.base_behavior = "idle"
  state.base_frame = frame_for_behavior("idle")
  state.last_snapshot_ms = 0
  state.last_recompute_ms = 0
  state.last_errors = 0

  telemetry.setup(config, on_editor_event)
  client.start(config, on_core_message, function(code, signal)
    debug_log(("core exited: code=%s signal=%s; continuing with Lua fallback"):format(code, signal))
  end)

  recompute_target(true, "start")
  send_snapshot(true)
  start_snapshot_timer()
  schedule_blink()
  schedule_ambient()
end

function M.stop()
  if not state.running then return end
  state.running = false
  state.blink_token = state.blink_token + 1
  state.ambient_token = state.ambient_token + 1
  cancel_sequence(true)
  telemetry.stop()
  client.stop()
  stop_active_timer()
  if state.snapshot_timer and not state.snapshot_timer:is_closing() then
    state.snapshot_timer:stop()
    state.snapshot_timer:close()
  end
  state.snapshot_timer = nil
  renderer.stop()
  state.parent, state.buffer = nil, nil
  state.position, state.target, state.motion = nil, nil, nil
  state.trail_samples = {}
  state.transition, state.demo = nil, nil
end

function M.toggle(config)
  if state.running then M.stop() else M.start(config) end
end

function M.set_skin(name)
  local avatar = avatar_loader.load(name)
  state.config.skin = name
  if not state.running then
    state.avatar = avatar
    return true
  end

  cancel_sequence(true)
  state.avatar = avatar
  state.motion, state.position, state.target = nil, nil, nil
  state.trail_samples = {}
  renderer.reset_surface()
  state.base_behavior = "idle"
  state.base_frame = frame_for_behavior("idle")
  recompute_target(true, "skin")
  apply_intent(state.intent or { behavior = "idle" })
  return true
end

function M.demo(animation, duration_ms)
  if not state.running then return false, "familiar is not running" end
  if not state.avatar.animations[animation] then
    return false, ("unknown animation: %s"):format(tostring(animation))
  end
  if state.transition then return false, "wait for the current movement transition to finish" end
  if not state.position then return false, "no safe render position is available in the current window" end

  local duration = tonumber(duration_ms) or 4000
  duration = math.max(250, math.min(duration, 30000))
  state.demo = { animation = animation, until_ms = now_ms() + duration }
  play_sequence(animation, {
    force = true,
    loop = true,
    until_ms = state.demo.until_ms,
    on_done = function()
      state.demo = nil
      apply_intent(state.intent or { behavior = "idle" })
    end,
  })
  return true
end

function M.animation_names(config)
  local avatar = state.avatar or avatar_loader.load(config.skin)
  local names = vim.tbl_keys(avatar.animations)
  table.sort(names)
  return names
end

function M.status()
  return {
    running = state.running,
    core = client.running(),
    skin = state.avatar and state.avatar.id or (state.config and state.config.skin or nil),
    behavior = state.base_behavior,
    mode_family = state.mode_family,
    position = state.position,
    target = state.target,
    motion = state.motion and state.motion.kind or nil,
    intent = state.intent,
    demo = state.demo and state.demo.animation or nil,
    animation = state.config and {
      fps = state.config.animation.fps,
      duration_ms = state.config.animation.duration_ms,
      easing = state.config.animation.easing,
      trail = state.config.animation.trail.mode,
      stickiness = state.config.animation.stickiness.enabled,
    } or nil,
    stats = vim.deepcopy(state.stats),
    renderer = renderer.stats(),
  }
end

M._mode_family = mode_family

return M
