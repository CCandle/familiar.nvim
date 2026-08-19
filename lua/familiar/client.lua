local brain_state = require("familiar.brain_state")
local models = require("familiar.models")

local M = {}

local state = {
  job = nil,
  carry = "",
  stderr_carry = "",
  on_message = nil,
  on_exit = nil,
  config = nil,
}

local function debug_log(message)
  if state.config and state.config.debug then
    vim.schedule(function()
      vim.notify("familiar: " .. message, vim.log.levels.DEBUG)
    end)
  end
end

local function plugin_root()
  local files = vim.api.nvim_get_runtime_file("lua/familiar/init.lua", false)
  if #files == 0 then return nil end
  return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(files[1])))
end

local function resolve_binary(config)
  if config.core.bin and config.core.bin ~= "" then return vim.fn.expand(config.core.bin) end
  if vim.env.FAMILIAR_CORE_BIN and vim.env.FAMILIAR_CORE_BIN ~= "" then
    return vim.fn.expand(vim.env.FAMILIAR_CORE_BIN)
  end

  local root = plugin_root()
  if not root then return nil end
  local candidates = {
    root .. "/target/release/familiar-core",
    root .. "/target/debug/familiar-core",
  }
  for _, candidate in ipairs(candidates) do
    if vim.fn.executable(candidate) == 1 then return candidate end
  end
  return nil
end

local function brain_payload(config)
  local source = config.brain
  local api_key = source.api_key
  if (not api_key or api_key == "") and source.api_key_env and source.api_key_env ~= "" then
    api_key = vim.env[source.api_key_env]
  end

  local model_path = source.local_model.model_path
  if not model_path or model_path == "" then model_path = models.path() end

  return {
    enabled = source.enabled == true,
    provider = source.provider,
    model = source.model,
    endpoint = source.endpoint,
    base_url = source.base_url,
    api_key = api_key,
    headers = vim.deepcopy(source.headers or {}),
    extra_body = vim.deepcopy(source.extra_body or {}),
    interval_ms = source.interval_ms,
    event_min_interval_ms = source.event_min_interval_ms,
    choice_ttl_ms = source.choice_ttl_ms,
    timeout_ms = source.timeout_ms,
    max_tokens = source.max_tokens,
    temperature = source.temperature,
    ["local"] = {
      model_path = model_path,
      n_ctx = source.local_model.n_ctx,
      n_threads = source.local_model.n_threads,
      n_gpu_layers = source.local_model.n_gpu_layers,
    },
  }
end

local function handle_line(line)
  if line == "" then return end
  local ok, message = pcall(vim.json.decode, line)
  if not ok then
    debug_log("invalid core message: " .. tostring(message))
    return
  end
  brain_state.handle(message)
  if state.on_message then state.on_message(message) end
end

local function consume_stdout(data)
  if not data or #data == 0 then return end
  data = vim.deepcopy(data)
  data[1] = state.carry .. data[1]
  state.carry = table.remove(data) or ""
  for _, line in ipairs(data) do handle_line(line) end
end

local function consume_stderr(data)
  if not data or #data == 0 then return end
  data = vim.deepcopy(data)
  data[1] = state.stderr_carry .. data[1]
  state.stderr_carry = table.remove(data) or ""
  for _, line in ipairs(data) do
    if line ~= "" then debug_log("core: " .. line) end
  end
end

function M.start(config, on_message, on_exit)
  state.config = config
  state.on_message = on_message
  state.on_exit = on_exit
  if state.job and state.job > 0 then return true end
  if not config.core.enabled then return false end

  local bin = resolve_binary(config)
  if not bin then
    debug_log("familiar-core not found; using Lua fallback")
    return false
  end

  brain_state.reset()
  state.carry = ""
  state.stderr_carry = ""
  local job
  job = vim.fn.jobstart({ bin }, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data) consume_stdout(data) end,
    on_stderr = function(_, data) consume_stderr(data) end,
    on_exit = function(_, code, signal)
      local was_current = state.job == job
      if was_current then state.job = nil end
      brain_state.disconnected()
      if state.on_exit then
        vim.schedule(function() state.on_exit(code, signal) end)
      end
    end,
  })

  if job <= 0 then
    debug_log("failed to start familiar-core")
    return false
  end

  state.job = job
  M.send({ type = "hello", protocol = 2, client = "familiar.nvim" })
  M.configure(config)
  return true
end

function M.send(message)
  if not state.job or state.job <= 0 then return false end
  local ok, encoded = pcall(vim.json.encode, message)
  if not ok then
    debug_log("failed to encode message: " .. tostring(encoded))
    return false
  end
  local sent = vim.fn.chansend(state.job, encoded .. "\n")
  return sent > 0
end

function M.configure(config)
  state.config = config
  if not M.running() then return false end
  brain_state.reconfiguring(config.brain.provider, config.brain.enabled)
  return M.send({ type = "configure", brain = brain_payload(config) })
end

function M.stop()
  local job = state.job
  if not job or job <= 0 then return end
  M.send({ type = "shutdown" })
  brain_state.disconnected()
  vim.defer_fn(function()
    if state.job == job then
      pcall(vim.fn.jobstop, job)
      state.job = nil
    end
  end, 250)
end

function M.running()
  return state.job ~= nil and state.job > 0
end

function M.binary(config)
  return resolve_binary(config)
end

M._brain_payload = brain_payload

return M
