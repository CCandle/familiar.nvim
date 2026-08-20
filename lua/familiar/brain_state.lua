local M = {}

local function fresh_state()
  return {
    connected = false,
    local_llama = nil,
    enabled = false,
    provider = "rule",
    state = "disconnected",
    error = nil,
    last_latency_ms = nil,
    last_choice = nil,
    consecutive_failures = 0,
    total_requests = 0,
    total_successes = 0,
  }
end

local state = fresh_state()

function M.reset()
  state = fresh_state()
end

function M.reconfiguring(provider, enabled)
  state.enabled = enabled == true
  state.provider = provider or state.provider
  state.state = "reconfiguring"
  state.error = nil
  state.last_latency_ms = nil
  state.last_choice = nil
  state.consecutive_failures = 0
  state.total_requests = 0
  state.total_successes = 0
end

function M.handle(message)
  if message.type == "ready" then
    state.connected = true
    state.local_llama = message.local_llama == true
  elseif message.type == "brain_status" then
    state.connected = true
    state.enabled = message.enabled == true
    state.provider = message.provider or state.provider
    state.state = message.state or state.state
    state.error = message.error
    state.last_latency_ms = message.last_latency_ms
    state.last_choice = message.last_choice
    state.consecutive_failures = message.consecutive_failures or 0
    state.total_requests = message.total_requests or 0
    state.total_successes = message.total_successes or 0
  end
end

function M.disconnected()
  state.connected = false
  state.state = "disconnected"
end

function M.get()
  return vim.deepcopy(state)
end

return M
