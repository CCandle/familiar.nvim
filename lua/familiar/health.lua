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
    vim.health.warn("termguicolors is disabled; the pixel palette will be degraded")
  end

  local ok_avatar, avatar = pcall(require("familiar.avatar").load, "fox")
  if ok_avatar then
    vim.health.ok(("default avatar loaded: %s (%dx%d logical pixels)"):format(avatar.id, avatar.width, avatar.height))
  else
    vim.health.error("default avatar failed validation: " .. tostring(avatar))
  end

  local config = require("familiar.config").resolve({})
  local core = require("familiar.client").binary(config)
  if core then
    vim.health.ok("familiar-core found: " .. core)
  elseif vim.fn.executable("cargo") == 1 then
    vim.health.warn("familiar-core is not built; Lua fallback will be used", {
      "Run: cargo build --release -p familiar-core",
    })
  else
    vim.health.info("familiar-core is unavailable and Cargo is not installed; Lua fallback remains usable")
  end

  local status = require("familiar").status()
  vim.health.info(("runtime=%s, core=%s, avatar=%s"):format(
    status.running and "running" or "stopped",
    status.core and "connected" or "disconnected",
    status.avatar or "not loaded"
  ))

  if vim.env.TERM_PROGRAM == "iTerm.app" then
    vim.health.info("terminal: iTerm2")
  elseif vim.env.TERM_PROGRAM and vim.env.TERM_PROGRAM ~= "" then
    vim.health.info("terminal: " .. vim.env.TERM_PROGRAM)
  end
end

return M
