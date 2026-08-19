local avatar_mod = require("familiar.avatar")
local brain_state = require("familiar.brain_state")
local client = require("familiar.client")
local config_mod = require("familiar.config")
local models = require("familiar.models")
local runtime = require("familiar.runtime")
local telemetry = require("familiar.telemetry")

local M = {}
local config = config_mod.resolve({})
local commands_created = false

local function set_skin(name)
  avatar_mod.load(name)
  if runtime.status().running then runtime.set_skin(name) end
  config.skin = name
  return name
end

local function brain_status()
  return {
    configured = {
      enabled = config.brain.enabled,
      provider = config.brain.provider,
      model = config.brain.model,
      endpoint = config.brain.endpoint,
      base_url = config.brain.base_url,
      interval_ms = config.brain.interval_ms,
      include_buffer_text = config.brain.context.include_buffer_text,
    },
    core = brain_state.get(),
    local_model = models.status(),
    core_binary = client.binary(config),
  }
end

local function resolve_brain_update(opts)
  local candidate = config_mod.resolve(vim.tbl_deep_extend("force", vim.deepcopy(config), {
    brain = opts or {},
  }))
  return candidate.brain
end

local function apply_brain_update(opts)
  config.brain = resolve_brain_update(opts)
  if client.running() then client.configure(config) end
  return brain_status()
end

local function reload_brain()
  if not client.running() then return false, "familiar-core is not running" end
  local ok = client.configure(config)
  return ok, ok and "BrainProvider configuration reloaded" or "failed to send BrainProvider configuration"
end

local function test_brain(callback)
  callback = callback or function() end
  if not config.brain.enabled or config.brain.provider == "rule" then
    callback({ ok = false, error = "AI brain is disabled; choose local_llama, ollama, or openai_compatible first" })
    return false
  end

  if not runtime.status().running then runtime.start(config) end
  if not client.running() then
    callback({ ok = false, error = "familiar-core is unavailable; the AI providers require the Rust sidecar" })
    return false
  end

  local snapshot = telemetry.snapshot(config)
  if not snapshot then
    callback({ ok = false, error = "no ordinary editor buffer is available for the brain probe" })
    return false
  end

  return client.probe(snapshot, callback)
end

local function notify_model_result(action, ok, message)
  if ok then
    vim.notify("familiar brain: " .. action .. " complete\n" .. tostring(message), vim.log.levels.INFO)
  else
    vim.notify("familiar brain: " .. action .. " failed\n" .. tostring(message), vim.log.levels.ERROR)
  end
end

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
    local status = runtime.status()
    status.brain = brain_status()
    vim.notify(vim.inspect(status), vim.log.levels.INFO, { title = "familiar.nvim" })
  end, { desc = "Show familiar.nvim status" })

  vim.api.nvim_create_user_command("FamiliarBrainStatus", function()
    vim.notify(vim.inspect(brain_status()), vim.log.levels.INFO, { title = "familiar.nvim brain" })
  end, { desc = "Show BrainProvider, reliability metrics, and managed-model status" })

  vim.api.nvim_create_user_command("FamiliarBrainReload", function()
    local ok, message = reload_brain()
    vim.notify("familiar brain: " .. message, ok and vim.log.levels.INFO or vim.log.levels.WARN)
  end, { desc = "Reload BrainProvider configuration and environment-sourced credentials" })

  vim.api.nvim_create_user_command("FamiliarBrainTest", function()
    vim.notify(
      ("familiar brain: probing %s%s …"):format(
        config.brain.provider,
        config.brain.model and (" / " .. config.brain.model) or ""
      ),
      vim.log.levels.INFO
    )
    test_brain(function(result)
      if result.ok then
        vim.notify(
          ("familiar brain: probe PASS\nprovider=%s  choice=%s  latency=%sms"):format(
            config.brain.provider,
            tostring(result.choice),
            tostring(result.latency_ms)
          ),
          vim.log.levels.INFO
        )
      else
        vim.notify("familiar brain: probe FAIL\n" .. tostring(result.error), vim.log.levels.ERROR)
      end
    end)
  end, { desc = "Run one side-effect-free inference through the configured BrainProvider" })

  vim.api.nvim_create_user_command("FamiliarBrainInstall", function()
    local bin = client.binary(config)
    local model = models.default
    vim.notify(
      ("familiar brain: downloading %s (~%.0f MB, %s) to\n%s"):format(
        model.id,
        model.approx_bytes / 1000000,
        model.license,
        models.path(model)
      ),
      vim.log.levels.INFO
    )
    models.install(bin, model, function(ok, message)
      notify_model_result("install", ok, message)
    end)
  end, { desc = "Download and verify the managed local GGUF brain model" })

  vim.api.nvim_create_user_command("FamiliarBrainRemove", function()
    models.remove(client.binary(config), models.default, function(ok, message)
      notify_model_result("remove", ok, message)
    end)
  end, { desc = "Remove the managed local GGUF brain model" })

  vim.api.nvim_create_user_command("FamiliarSkin", function(opts)
    local name = opts.args
    if name == "" then
      vim.notify("familiar skin: " .. tostring(config.skin), vim.log.levels.INFO)
      return
    end
    local ok, err = pcall(set_skin, name)
    if not ok then vim.notify("familiar skin: " .. tostring(err), vim.log.levels.WARN) end
  end, {
    nargs = "?",
    desc = "Show or switch the familiar skin",
    complete = function() return avatar_mod.names() end,
  })

  vim.api.nvim_create_user_command("FamiliarDemo", function(opts)
    if not runtime.status().running then runtime.start(config) end
    local animation = opts.fargs[1]
    local duration_ms = opts.fargs[2] and tonumber(opts.fargs[2]) or nil
    if opts.fargs[2] and not duration_ms then
      vim.notify("familiar demo: duration must be milliseconds", vim.log.levels.WARN)
      return
    end
    local ok, err = runtime.demo(animation, duration_ms)
    if not ok then vim.notify("familiar demo: " .. tostring(err), vim.log.levels.WARN) end
  end, {
    nargs = "+",
    desc = "Temporarily force one skin animation: :FamiliarDemo <animation> [duration_ms]",
    complete = function(_, cmdline)
      local _, spaces = cmdline:gsub(" ", "")
      if spaces > 1 then return {} end
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
    callback = function() runtime.stop() end,
  })

  if config.enabled and #vim.api.nvim_list_uis() > 0 then runtime.start(config) end
end

function M.start() runtime.start(config) end
function M.stop() runtime.stop() end
function M.toggle() runtime.toggle(config) end

function M.skin(name)
  if name == nil then return config.skin end
  return set_skin(name)
end

function M.brain(opts)
  if opts == nil then return brain_status() end
  return apply_brain_update(opts)
end

function M.brain_reload()
  return reload_brain()
end

function M.brain_test(callback)
  return test_brain(callback)
end

function M.brain_status()
  return brain_status()
end

function M.demo(animation, duration_ms)
  if not runtime.status().running then runtime.start(config) end
  return runtime.demo(animation, duration_ms)
end

function M.status()
  local status = runtime.status()
  status.brain = brain_status()
  return status
end

return M
