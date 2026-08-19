local M = {}

M.animation_profiles = {
  balanced = { fps = 60, duration_ms = 250, easing = "cubic" },
  high_refresh = { fps = 120, duration_ms = 250, easing = "cubic" },
  economy = { fps = 30, duration_ms = 280, easing = "cubic" },
}

M.defaults = {
  enabled = true,
  debug = false,
  skin = "mote",

  core = {
    enabled = true,
    bin = nil,
  },

  brain = {
    enabled = false,
    provider = "rule", -- rule | local_llama | ollama | openai_compatible
    model = nil,
    endpoint = nil,
    api_key = nil,
    api_key_env = nil,
    interval_ms = 20000,
    event_min_interval_ms = 5000,
    choice_ttl_ms = 30000,
    timeout_ms = 8000,
    max_tokens = 8,
    temperature = 0.15,

    context = {
      include_buffer_text = true,
      lines_before = 6,
      lines_after = 6,
      max_line_chars = 240,
      max_total_chars = 3200,
    },

    local_model = {
      model_path = nil,
      n_ctx = 2048,
      n_threads = 4,
      n_gpu_layers = 99,
    },
  },

  render = {
    margin = 1,
    min_width = 36,
    min_height = 8,
    warp_distance = 40,
    max_candidates = 8,
    recompute_throttle_ms = 80,
  },

  animation = {
    profile = "balanced",
    fps = nil,
    duration_ms = nil,
    easing = nil,

    motion = {
      run_distance = 10,
      dash_distance = 26,
      dash_duration_ms = 190,
      retarget_min_remaining_ms = 70,
      retarget_max_extend_ms = 80,
    },

    trail = {
      mode = "auto",
      min_distance = 7,
      sample_ms = 38,
      lifetime_ms = 180,
      max_samples = 4,
    },

    stickiness = {
      enabled = true,
      utility_threshold = 0.18,
      distance_cost = 0.45,
      distance_scale = 24,
      recent_move_window_ms = 700,
      recent_move_cost = 0.35,
      moving_cost = 0.15,
    },

    expression = {
      motion_pose_ms = 85,
      blink_min_ms = 2800,
      blink_max_ms = 6200,
      ambient_min_ms = 12000,
      ambient_max_ms = 28000,
      save_reaction_cooldown_ms = 12000,
      diagnostic_reaction_cooldown_ms = 8000,
    },
  },

  interaction = {
    mode_reaction_cooldown_ms = 120,
    modes = {
      normal = { movement = "allow", utility_bias = 0.00, ambient = true },
      insert = { movement = "avoid", utility_bias = -0.25, ambient = false },
      visual = { movement = "avoid", utility_bias = -0.20, ambient = false },
      operator = { movement = "avoid", utility_bias = -0.20, ambient = false },
      replace = { movement = "avoid", utility_bias = -0.25, ambient = false },
      command = { movement = "freeze", utility_bias = -0.35, ambient = false },
      terminal = { movement = "freeze", utility_bias = -0.35, ambient = false },
      prompt = { movement = "freeze", utility_bias = -0.50, ambient = false },
    },
  },

  telemetry = {
    snapshot_ms = 1200,
    max_visible_lines = 120,
  },
}

local function validate(resolved)
  if resolved.animation.fps < 1 or resolved.animation.fps > 240 then
    error("familiar.nvim: animation.fps must be in 1..240")
  end
  if resolved.animation.duration_ms < 1 then
    error("familiar.nvim: animation.duration_ms must be positive")
  end

  local easing_names = {
    linear = true, quad = true, out_quad = true, cubic = true, out_cubic = true, quart = true, out_quart = true,
  }
  if not easing_names[resolved.animation.easing] then
    error(("familiar.nvim: unknown animation easing %q"):format(tostring(resolved.animation.easing)))
  end
  if resolved.animation.trail.max_samples < 0 then
    error("familiar.nvim: animation.trail.max_samples must be non-negative")
  end

  local trail_mode = resolved.animation.trail.mode
  if trail_mode ~= "none" and trail_mode ~= "auto" and trail_mode ~= "always" then
    error("familiar.nvim: animation.trail.mode must be 'none', 'auto', or 'always'")
  end

  local providers = {
    rule = true,
    local_llama = true,
    ollama = true,
    openai_compatible = true,
  }
  if not providers[resolved.brain.provider] then
    error(("familiar.nvim: unknown brain provider %q"):format(tostring(resolved.brain.provider)))
  end
  if resolved.brain.interval_ms < 1000 then
    error("familiar.nvim: brain.interval_ms must be >= 1000")
  end
  if resolved.brain.event_min_interval_ms < 500 then
    error("familiar.nvim: brain.event_min_interval_ms must be >= 500")
  end
  if resolved.brain.max_tokens < 1 or resolved.brain.max_tokens > 64 then
    error("familiar.nvim: brain.max_tokens must be in 1..64")
  end
  if resolved.brain.temperature < 0 or resolved.brain.temperature > 2 then
    error("familiar.nvim: brain.temperature must be in 0..2")
  end
  if resolved.brain.context.max_total_chars < 0 then
    error("familiar.nvim: brain.context.max_total_chars must be non-negative")
  end

  return resolved
end

function M.resolve(opts)
  opts = opts or {}
  local user = vim.deepcopy(opts)

  if user.skin == nil and user.avatar ~= nil then user.skin = user.avatar end
  user.avatar = nil

  local profile_name = (user.animation and user.animation.profile) or M.defaults.animation.profile
  local profile = M.animation_profiles[profile_name]
  if not profile then
    error(("familiar.nvim: unknown animation profile %q"):format(tostring(profile_name)))
  end

  local resolved = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user)
  resolved.animation.profile = profile_name
  resolved.animation.fps = resolved.animation.fps or profile.fps
  resolved.animation.duration_ms = resolved.animation.duration_ms or profile.duration_ms
  resolved.animation.easing = resolved.animation.easing or profile.easing

  return validate(resolved)
end

return M
