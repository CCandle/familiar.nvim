local avatar_loader = require("familiar.avatar")
local client = require("familiar.client")
local renderer = require("familiar.renderer")
local telemetry = require("familiar.telemetry")

local M = {}

local state = {
  running = false,
  config = nil,
  avatar = nil,
  timer = nil,
  parent = nil,
  buffer = nil,
  position = nil,
  target = nil,
  animation = "idle",
  frame_index = 1,
  transition = nil,
  intent = nil,
  seq = 0,
  last_snapshot = 0,
  last_relocate = 0,
}

local function now()
  return vim.uv.now()
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

local function set_animation(name, restart)
  if not state.avatar.animations[name] then
    name = "idle"
  end
  if restart or state.animation ~= name then
    state.animation = name
    state.frame_index = 1
  end
end

local function animation_frame()
  local animation = state.avatar.animations[state.animation] or state.avatar.animations.idle
  local frames = animation.frames
  local index = math.min(state.frame_index, #frames)
  local frame = frames[index]
  local completed = false

  state.frame_index = state.frame_index + 1
  if state.frame_index > #frames then
    if animation.loop then
      state.frame_index = 1
    else
      state.frame_index = #frames
      completed = true
    end
  end

  return frame, completed, animation
end

local function local_intent(snapshot)
  if not snapshot then return { behavior = "idle" } end
  if snapshot.activity.idle_ms >= 120000 then
    return { behavior = "sleep", mood = "sleepy" }
  end
  if snapshot.activity.typing or snapshot.mode:sub(1, 1) == "i" then
    return { behavior = "focus", mood = "focused" }
  end
  if snapshot.diagnostics.errors > 0 then
    return { behavior = "inspect", mood = "concerned", emote = "question" }
  end
  return { behavior = "idle", mood = "calm" }
end

local function apply_intent(intent)
  state.intent = intent
  if state.transition or not state.position then return end
  if intent.behavior == "sleep" then
    set_animation("sleep")
  elseif intent.behavior == "focus" then
    set_animation("focus")
  elseif intent.behavior == "hide" then
    state.transition = { kind = "hide" }
    set_animation("vanish", true)
  elseif intent.behavior == "curious" then
    set_animation("idle")
  elseif intent.behavior == "inspect" then
    set_animation("idle")
  else
    set_animation("idle")
  end
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
  local t = now()
  if not force and t - state.last_snapshot < state.config.telemetry.snapshot_ms then
    return
  end
  state.last_snapshot = t
  local snapshot = telemetry.snapshot(state.config)
  if not snapshot then return end

  if client.running() then
    state.seq = state.seq + 1
    client.send({ type = "snapshot", seq = state.seq, snapshot = snapshot })
  else
    apply_intent(local_intent(snapshot))
  end
end

local function distance(a, b)
  if not a or not b then return math.huge end
  return math.abs(a.x - b.x) + math.abs(a.y - b.y)
end

local function begin_relocation(target)
  if not target then
    if state.position then
      state.transition = { kind = "hide" }
      set_animation("vanish", true)
    else
      renderer.hide()
    end
    state.target = nil
    return
  end

  state.target = target
  if not state.position then
    state.position = { x = target.x, y = target.y }
    state.transition = { kind = "appear" }
    set_animation("appear", true)
    return
  end

  local dist = distance(state.position, target)
  if dist == 0 then return end

  if dist >= state.config.render.warp_distance then
    state.transition = { kind = "warp", target = { x = target.x, y = target.y } }
    set_animation("vanish", true)
  else
    set_animation(dist > 12 and "run" or "walk", true)
  end
end

local function recompute_target(force)
  local parent, buf = normal_parent()
  if not parent then
    begin_relocation(nil)
    return
  end

  local t = now()
  if not force and t - state.last_relocate < 450 then
    return
  end
  state.last_relocate = t

  local changed_context = state.parent ~= parent or state.buffer ~= buf
  state.parent = parent
  state.buffer = buf
  local target = renderer.find_safe_position(parent, state.avatar, state.config.render)

  if changed_context then
    state.position = target and { x = target.x, y = target.y } or nil
    state.target = target
    if target then
      state.transition = { kind = "appear" }
      set_animation("appear", true)
    else
      renderer.hide()
    end
    return
  end

  begin_relocation(target)
end

local function approach(current, target, step)
  local delta = target - current
  if math.abs(delta) <= step then return target end
  return current + (delta > 0 and step or -step)
end

local function advance_motion()
  if state.transition or not state.position or not state.target then return end
  if distance(state.position, state.target) == 0 then
    apply_intent(state.intent or { behavior = "idle" })
    return
  end

  local step = state.config.render.move_step
  state.position.x = approach(state.position.x, state.target.x, step)
  state.position.y = approach(state.position.y, state.target.y, 1)

  local remaining = distance(state.position, state.target)
  set_animation(remaining > 12 and "run" or "walk")
end

local function finish_transition(animation)
  if not state.transition then
    if animation.next then
      set_animation(animation.next, true)
    end
    return
  end

  local transition = state.transition
  if transition.kind == "warp" then
    state.position = transition.target
    state.target = transition.target
    state.transition = { kind = "appear" }
    set_animation("appear", true)
  elseif transition.kind == "hide" then
    renderer.hide()
    state.position = nil
    state.target = nil
    state.transition = nil
    set_animation("idle", true)
  elseif transition.kind == "appear" then
    state.transition = nil
    apply_intent(state.intent or { behavior = "idle" })
  end
end

local function tick()
  if not state.running then return end
  local parent, buf = normal_parent()
  if not parent then
    renderer.hide()
    return
  end

  if parent ~= state.parent or buf ~= state.buffer then
    recompute_target(true)
  end

  advance_motion()
  local frame, completed, animation = animation_frame()
  if state.position then
    renderer.draw(state.parent, state.avatar, frame, state.position)
  else
    renderer.hide()
  end

  if completed then
    finish_transition(animation)
  end

  send_snapshot(false)
end

local function on_editor_event(kind, args)
  if not state.running then return end
  local relocation_event = kind == "buffer_enter"
    or kind == "winresized"
    or kind == "winscrolled"
    or kind == "diagnosticchanged"

  if relocation_event then
    recompute_target(kind == "buffer_enter" or kind == "winresized")
  end

  if client.running() and kind ~= "cursor_moved" and kind ~= "typing" then
    state.seq = state.seq + 1
    client.send({
      type = "event",
      seq = state.seq,
      event = {
        kind = kind,
        buffer = args and args.buf or nil,
      },
    })
  end

  if kind == "buffer_enter" or kind == "diagnosticchanged" then
    send_snapshot(true)
  end
end

function M.start(config)
  if state.running then return end
  state.config = config
  state.avatar = avatar_loader.load(config.avatar)
  state.running = true
  state.intent = { behavior = "idle" }
  state.animation = "idle"
  state.frame_index = 1
  state.position = nil
  state.target = nil
  state.transition = nil
  state.last_snapshot = 0
  state.last_relocate = 0

  telemetry.setup(config, on_editor_event)
  client.start(config, on_core_message, function(code, signal)
    debug_log(("core exited: code=%s signal=%s; continuing with Lua fallback"):format(code, signal))
  end)

  recompute_target(true)
  send_snapshot(true)

  state.timer = vim.uv.new_timer()
  state.timer:start(config.render.frame_ms, config.render.frame_ms, vim.schedule_wrap(tick))
end

function M.stop()
  if not state.running then return end
  state.running = false
  telemetry.stop()
  client.stop()
  if state.timer and not state.timer:is_closing() then
    state.timer:stop()
    state.timer:close()
  end
  state.timer = nil
  renderer.stop()
  state.parent = nil
  state.buffer = nil
  state.position = nil
  state.target = nil
  state.transition = nil
end

function M.toggle(config)
  if state.running then
    M.stop()
  else
    M.start(config)
  end
end

function M.status()
  return {
    running = state.running,
    core = client.running(),
    animation = state.animation,
    avatar = state.avatar and state.avatar.id or nil,
    position = state.position,
    target = state.target,
    intent = state.intent,
  }
end

return M
