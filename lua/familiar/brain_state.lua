local M = {}

local state = {
  connected = false,
  local_llama = nil,
  enabled = false,
  provider = "rule",
  state = "disconnected",
  error = nil,
}

function M.reset()
  state = {
    connected = false,
    local_llama = nil,
    enabled = false,
    provider = "rule",
    state = "disconnected",
    error = nil,
  }
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
