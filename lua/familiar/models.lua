local M = {}
local uv = vim.uv or vim.loop

M.default = {
  id = "smollm2-135m-instruct-q4_k_m",
  file = "SmolLM2-135M-Instruct-Q4_K_M.gguf",
  url = "https://huggingface.co/lmstudio-community/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q4_K_M.gguf",
  sha256 = "bda484992f9655d22504b14e57985257fa6a86937c61f957cf99c10a3bcae169",
  license = "Apache-2.0",
  approx_bytes = 105000000,
}

function M.path(model)
  model = model or M.default
  return vim.fs.joinpath(vim.fn.stdpath("data"), "familiar", "models", model.file)
end

local function gguf_ok(path)
  local file = io.open(path, "rb")
  if not file then return false end
  local magic = file:read(4)
  file:close()
  return magic == "GGUF"
end

function M.status(model)
  model = model or M.default
  local path = M.path(model)
  local stat = uv.fs_stat(path)
  return {
    id = model.id,
    path = path,
    installed = stat ~= nil and gguf_ok(path),
    bytes = stat and stat.size or 0,
    sha256 = model.sha256,
    license = model.license,
    approx_bytes = model.approx_bytes,
  }
end

local function run_model_command(bin, args, callback)
  if not bin or bin == "" then
    callback(false, "familiar-core is not built")
    return
  end
  if not vim.system then
    callback(false, "Neovim vim.system is unavailable")
    return
  end

  local command = { bin, "model" }
  vim.list_extend(command, args)
  vim.system(command, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        callback(true, result.stdout and vim.trim(result.stdout) or "")
      else
        local message = result.stderr and vim.trim(result.stderr) or "model command failed"
        callback(false, message)
      end
    end)
  end)
end

function M.install(bin, model, callback)
  model = model or M.default
  callback = callback or function() end
  local path = M.path(model)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  run_model_command(bin, { "install", path, model.url }, callback)
end

function M.remove(bin, model, callback)
  model = model or M.default
  callback = callback or function() end
  run_model_command(bin, { "remove", M.path(model) }, callback)
end

return M
