local easing = require("familiar.easing")

local M = {}

local function distance(a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  return math.sqrt(dx * dx + dy * dy)
end

local function copy_point(p)
  return { x = p.x, y = p.y }
end

function M.distance(a, b)
  return distance(a, b)
end

function M.utility(ctx, opts)
  opts = opts or {}
  local semantic_value = ctx.semantic_value or 0
  local d = ctx.distance or 0
  local distance_scale = math.max(1, opts.distance_scale or 24)
  local distance_cost = math.min(d / distance_scale, 1) * (opts.distance_cost or 0.45)

  local recent_move_cost = 0
  local since_last = ctx.since_last_move_ms or math.huge
  local recent_window = math.max(1, opts.recent_move_window_ms or 700)
  if since_last < recent_window then
    recent_move_cost = (1 - since_last / recent_window) * (opts.recent_move_cost or 0.35)
  end

  local moving_cost = ctx.in_motion and (opts.moving_cost or 0.15) or 0
  local mode_bias = ctx.mode_bias or 0
  return semantic_value + mode_bias - distance_cost - recent_move_cost - moving_cost
end

function M.should_move(ctx, opts)
  if ctx.force then return true, math.huge end
  if ctx.current_safe and ctx.movement == "freeze" then return false, -math.huge end

  local score = M.utility(ctx, opts)
  return score >= (opts.utility_threshold or 0.18), score
end

function M.begin(position, target, now_ms, duration_ms, kind, easing_name)
  local plan = {
    from = copy_point(position),
    target = copy_point(target),
    started_ms = now_ms,
    deadline_ms = now_ms + math.max(1, duration_ms),
    kind = kind or "walk",
    easing = easing_name or "cubic",
  }
  plan.distance = distance(plan.from, plan.target)
  return plan
end

function M.retarget(plan, current, target, now_ms, opts)
  opts = opts or {}
  local remaining = plan.deadline_ms - now_ms
  local min_remaining = opts.retarget_min_remaining_ms or 70
  local extended = 0

  if remaining < min_remaining then
    extended = math.min(opts.retarget_max_extend_ms or 80, min_remaining - remaining)
    plan.deadline_ms = plan.deadline_ms + extended
  end

  plan.from = copy_point(current)
  plan.target = copy_point(target)
  plan.started_ms = now_ms
  plan.distance = distance(plan.from, plan.target)
  return extended
end

function M.sample(plan, now_ms)
  local total = math.max(1, plan.deadline_ms - plan.started_ms)
  local raw = (now_ms - plan.started_ms) / total
  if raw >= 1 then
    return copy_point(plan.target), true, 1
  end

  local p = easing.apply(plan.easing, raw)
  return {
    x = plan.from.x + (plan.target.x - plan.from.x) * p,
    y = plan.from.y + (plan.target.y - plan.from.y) * p,
  }, false, p
end

return M
