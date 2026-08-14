local config_mod = require("familiar.config")
local runtime = require("familiar.runtime")

local M = {}
local config = config_mod.resolve({})
local commands_created = false

local function create_commands()
  if commands_created then return end
  commands_created = true

  vim.api.nvim_create_user_command("FamiliarStart", function()
    runtime.start(config)
  end, { desc = "Start familiar.nvim" })

  vim.api.nvim_create_user_command("FamiliarStop", function()
    runtime.stop()
  end, { desc = "Stop familiar.nvim" })

  vim.api.nvim_create_user_command("FamiliarToggle", function()
    runtime.toggle(config)
  end, { desc = "Toggle familiar.nvim" })

  vim.api.nvim_create_user_command("FamiliarStatus", function()
    vim.notify(vim.inspect(runtime.status()), vim.log.levels.INFO, { title = "familiar.nvim" })
  end, { desc = "Show familiar.nvim status" })

  vim.api.nvim_create_user_command("FamiliarDemo", function(opts)
    if not runtime.status().running then
      runtime.start(config)
    end
    local ok, err = runtime.demo(opts.args, opts.count > 0 and opts.count or nil)
    if not ok then
      vim.notify("familiar demo: " .. tostring(err), vim.log.levels.WARN)
    end
  end, {
    nargs = 1,
    count = true,
    desc = "Temporarily force one avatar animation (count = duration ms)",
    complete = function()
      return runtime.animation_names(config)
    end,
  })
end

function M.setup(opts)
  if vim.fn.has("nvim-0.12") ~= 1 then
    error("familiar.nvim requires Neovim >= 0.12")
  end

  config = config_mod.resolve(opts)
  create_commands()

  local group = vim.api.nvim_create_augroup("FamiliarLifecycle", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      runtime.stop()
    end,
  })

  if config.enabled and #vim.api.nvim_list_uis() > 0 then
    runtime.start(config)
  end
end

function M.start()
  runtime.start(config)
end

function M.stop()
  runtime.stop()
end

function M.toggle()
  runtime.toggle(config)
end

function M.demo(animation, duration_ms)
  if not runtime.status().running then
    runtime.start(config)
  end
  return runtime.demo(animation, duration_ms)
end

function M.status()
  return runtime.status()
end

return M
