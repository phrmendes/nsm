--- Run the `nsm` command and report its failures.
---
---@tag nsm-cli
---@private

local cli = {}

--- Exit code of `nsm kill` when it refuses a change because of unsaved buffers.
---
---@private
cli.UNSAVED = 3

--- Strip the ANSI colour codes from a CLI message.
---
---@param text string|nil
---@return string
---@private
local function strip_ansi(text)
  local stripped = (text or ""):gsub("\27%[[%d;]*m", "")
  return stripped
end

--- Notify an error, without the ANSI colour codes of the CLI.
---
---@param err any
---@private
function cli.notify_error(err) vim.notify(strip_ansi(tostring(err)), vim.log.levels.ERROR) end

--- Return the message of a failed command.
---
---@param command string[]
---@param result vim.SystemCompleted
---@return string
---@private
function cli.get_message(command, result)
  local stderr = strip_ansi((result.stderr or ""):gsub("%s+$", ""))
  return stderr ~= "" and stderr or ("`" .. table.concat(command, " ") .. "` failed")
end

--- Notify the failure of a command.
---
---@param command string[]
---@param result vim.SystemCompleted
---@private
local function fail(command, result) cli.notify_error(cli.get_message(command, result)) end

--- Run a command and call `on_success` with its trimmed stdout.
---
--- The callback runs after `nsm` exits, so Neovim stays responsive. A failure
--- calls `on_failure` with the result, or notifies when `on_failure` is missing.
---
---@param command string[]
---@param on_success fun(stdout: string)
---@param on_failure fun(result: vim.SystemCompleted)|nil
---@private
function cli.run(command, on_success, on_failure)
  local on_error = on_failure or function(result) fail(command, result) end

  local on_exit = vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      on_error(result)
      return
    end

    on_success(vim.trim(result.stdout or ""))
  end)

  local ok, process = pcall(vim.system, command, { text = true }, on_exit)
  if not ok then cli.notify_error(process) end
end

return cli
