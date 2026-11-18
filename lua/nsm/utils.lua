--- Internal helpers of nsm: run the `nsm` command and report its results.
---
---@private

local utils = {}

---@param text string|nil
---@return string
---@private
local function strip_ansi(text)
  local stripped = (text or ""):gsub("\27%[[%d;]*m", "")
  return stripped
end

--- Show a message without ANSI colour codes, unless the message is empty.
---
---@param message any
---@param level integer|nil
---@private
function utils.notify(message, level)
  local text = strip_ansi(tostring(message))
  if text ~= "" then vim.notify(text, level) end
end

---@param command string[]
---@param result vim.SystemCompleted
---@return string
---@private
function utils.get_message(command, result)
  local stderr = strip_ansi((result.stderr or ""):gsub("%s+$", ""))
  return stderr ~= "" and stderr or ("`" .. table.concat(command, " ") .. "` failed")
end

--- Run a command and call `on_success` with its trimmed stdout.
---
--- The callback runs after `nsm` exits, so Neovim stays responsive. A failure
--- calls `on_failure` with the result, or notifies when `on_failure` is missing.
---
---@param command string[]
---@param on_success fun(stdout: string)
---@param on_failure fun(result: vim.SystemCompleted)|nil
---@private
function utils.run(command, on_success, on_failure)
  local on_error = on_failure or function(result) utils.notify(utils.get_message(command, result), vim.log.levels.ERROR) end

  local on_exit = vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      on_error(result)
      return
    end

    on_success(vim.trim(result.stdout or ""))
  end)

  local ok, process = pcall(vim.system, command, { text = true }, on_exit)
  if not ok then utils.notify(process, vim.log.levels.ERROR) end
end

return utils
