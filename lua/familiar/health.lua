local M = {}

function M.check()
  vim.health.start("familiar.nvim")

  if vim.fn.has("nvim-0.12") == 1 then
    vim.health.ok("Neovim >= 0.12")
  else
    vim.health.error("Neovim >= 0.12 is required")
  end

  if vim.o.termguicolors then
    vim.health.ok("termguicolors is enabled")
  else
    vim.health.warn("termguicolors is disabled; familiar colors will be degraded")
  end

  local avatar_mod = require("familiar.avatar")
  for _, name in ipairs(avatar_mod.names()) do
    local ok_skin, skin = pcall(avatar_mod.load, name)
    if ok_skin then
      vim.health.ok(("skin loaded: %s (%s, %dx%d)"):format(skin.id, skin.kind or "pixel", skin.width, skin.height))
    else
      vim.health.error(("skin %s failed validation: %s"):format(name, tostring(skin)))
    end
  end

  local config = require("familiar.config").resolve({})
  vim.health.info(("animation profile=%s, fps=%d, duration=%dms, easing=%s, trail=%s"):format(
    config.animation.profile,
    config.animation.fps,
    config.animation.duration_ms,
    config.animation.easing,
    config.animation.trail.mode
  ))

  local client = require("familiar.client")
  local core = client.binary(config)
  if core then
    vim.health.ok("familiar-core found: " .. core)
  elseif vim.fn.executable("cargo") == 1 then
    vim.health.warn("familiar-core is not built; Lua fallback will be used", {
      "Run: cargo build --release -p familiar-core",
    })
  else
    vim.health.info("familiar-core is unavailable and Cargo is not installed; Lua fallback remains usable")
  end

  local brain = require("familiar.brain_state").get()
  local model = require("familiar.models").status()
  vim.health.info(("brain configured: enabled=%s provider=%s interval=%dms buffer_text=%s"):format(
    tostring(config.brain.enabled),
    config.brain.provider,
    config.brain.interval_ms,
    tostring(config.brain.context.include_buffer_text)
  ))

  if model.installed then
    vim.health.ok(("managed local model installed: %s (%.1f MB)"):format(model.id, model.bytes / 1000000))
  else
    vim.health.info(("managed local model not installed: %s (~%.0f MB, %s)"):format(
      model.id,
      model.approx_bytes / 1000000,
      model.license
    ))
  end

  if brain.connected then
    vim.health.info(("brain runtime: provider=%s state=%s local_llama=%s"):format(
      tostring(brain.provider),
      tostring(brain.state),
      tostring(brain.local_llama)
    ))
    if brain.error then vim.health.warn("brain provider error: " .. tostring(brain.error)) end
  elseif config.brain.enabled and config.brain.provider == "local_llama" then
    vim.health.info("local_llama requires a core built with: cargo build --release -p familiar-core --features local-llama")
  end

  local status = require("familiar").status()
  vim.health.info(("runtime=%s, core=%s, skin=%s"):format(
    status.running and "running" or "stopped",
    status.core and "connected" or "disconnected",
    status.skin or "not loaded"
  ))

  if vim.env.TERM_PROGRAM == "iTerm.app" then
    vim.health.info("terminal: iTerm2")
  elseif vim.env.TERM_PROGRAM and vim.env.TERM_PROGRAM ~= "" then
    vim.health.info("terminal: " .. vim.env.TERM_PROGRAM)
  end
end

return M
