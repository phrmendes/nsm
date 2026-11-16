--- *nsm.nvim* Neovim Server Manager
---
--- Open the session picker for the detached Neovim servers that nsm keeps.
---
--- `:Nsm` and the `<Plug>(nsm-switch)` mapping switch the current UI to the
--- chosen session with `:connect`.
---
--- Usage ~
--- *nsm-usage*
---
--- - `nsm attach [name-or-directory]`: create or open a session, or pick one.
--- - `nsm switch`: pick another session.
--- - `nsm last`: return to the previous session.
--- - `nsm new <name> [path]`: create a named session.
--- - `nsm start <name-or-directory>`: start a session and print its socket.
--- - `nsm list`: print sessions as a table.
--- - `nsm pick`: print the picker rows as JSON.
--- - `nsm kill [name]`: stop a session, or every session with `--all`.
--- - `nsm a`, `nsm s`, `nsm l`, `nsm n`, `nsm ls`, `nsm k`: short forms.
---
--- Pass `--scope <path>` to `attach`, `switch`, or `kill`, or set `NSM_SCOPE`,
--- to limit the picker to one directory. `nsm kill` refuses unsaved buffers;
--- pass `--force` to override it. `:detach` keeps the server running.
---
--- Configuration ~
--- *nsm-configuration*
---
--- Create `~/.config/.nsm.nuon`:
---
--- >
---   {
---     projects: ["~/Projects", "/mnt/external/projects"]
---     icons: { running: "🟢", stored: "⚫", directory: "📁" }
---     restore: { file: "Session.vim" }
---   }
--- <
---
--- `projects` lists all project roots. Omit it to disable repository discovery.
--- `PROJECTS_DIR` is not read. `restore.file` is optional and runs project
--- Vimscript, so enable it only for trusted projects.
---
--- SSH hosts ~
--- *nsm-ssh*
---
--- `:Nsm` also lists the `Host` aliases in `~/.ssh/config`, if Neovim supports
--- `:connect ssh://`. Choosing one connects to that host. Neovim uses the
--- `nvim` in the `PATH` of the host when that version is new enough, otherwise
--- it installs its own. It copies your local config to `~/.config/nvim-remote/`
--- and runs it with `NVIM_APPNAME=nvim-remote`. The remote host needs no `nsm`.
---
--- Picker rows ~
--- *nsm-rows*
---
--- `nsm pick` prints one JSON object per row. The fields are:
---
--- - `label`: the text that the picker shows.
--- - `name`: the session name, or null for a directory or a host.
--- - `path`: the directory, or null for a host.
--- - `source`: `running`, `stored`, `directory`, `zoxide`, or `host`.
--- - `address`: the `ssh://` address of a host row.
---
--- Requirements ~
--- *nsm-requirements*
---
--- - Neovim 0.12+ with `:connect ssh://` for SSH hosts
--- - `nsm` on `PATH`, plus `nvim` and `git`
--- - `fzf` on `PATH`
--- - `zoxide` on `PATH` for recent directories
---
---@tag nsm
---@tag :Nsm
---@tag <Plug>(nsm-switch)

---@class nsm.Config
---@field keymap string|false|nil Keymap for the session picker. Defaults to "<leader>w". Use false for no mapping.
---@field scope string|nil Only list rows under this directory.

local nsm = {}
local mapped
local scope

--- Strip the ANSI colour codes from a CLI message.
---
---@param text string|nil
---@return string
---@private
local function strip_ansi(text) return ((text or ""):gsub("\27%[[%d;]*m", "")) end

--- Notify an error, without the ANSI colour codes of the CLI.
---
---@param err any
---@private
local function notify_error(err) vim.notify(strip_ansi(tostring(err)), vim.log.levels.ERROR) end

--- Notify the failure of a command.
---
---@param command string[]
---@param result vim.SystemCompleted
---@private
local function fail(command, result)
  local stderr = (result.stderr or ""):gsub("%s+$", "")
  local fallback = "`" .. table.concat(command, " ") .. "` failed"
  notify_error(stderr ~= "" and stderr or fallback)
end

--- Run a command and return its trimmed stdout, or notify its failure.
---
---@param command string[]
---@return string|nil
---@private
local function run(command)
  local ok, result = pcall(function() return vim.system(command, { text = true }):wait() end)

  if not ok then
    notify_error(result)
    return nil
  end

  if result.code ~= 0 then
    fail(command, result)
    return nil
  end

  return ((result.stdout or ""):gsub("%s+$", ""))
end

--- Run a command and call `on_success` with its trimmed stdout.
---
--- The callback runs after `nsm` exits. A failure notifies instead.
---
---@param command string[]
---@param on_success fun(stdout: string)
---@private
local function run_async(command, on_success)
  local on_exit = vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      fail(command, result)
      return
    end

    on_success(vim.trim(result.stdout or ""))
  end)

  local ok, process = pcall(vim.system, command, { text = true }, on_exit)
  if not ok then notify_error(process) end
end

--- Return the name of the row, or its path when it has no session.
---
---@param item table
---@return string
---@private
local function get_target(item)
  if item.name and item.name ~= vim.NIL and item.name ~= "" then return item.name end
  return item.path
end

--- Return whether Neovim supports `:connect ssh://`.
---
---@return boolean
---@private
local function has_remote_ssh() return #vim.fn.getcompletion("remote-ssh", "help") > 0 end

--- Ask for a session or directory with `vim.ui.select`.
---
---@param on_choice fun(item: table)
---@private
local function pick(on_choice)
  local command = { "nsm", "pick" }
  if has_remote_ssh() then table.insert(command, "--hosts") end
  if scope and scope ~= "" then vim.list_extend(command, { "--scope", scope }) end

  local output = run(command)
  if not output then return end

  local ok, items = pcall(vim.json.decode, output)
  if not ok or type(items) ~= "table" then
    vim.notify("nsm returned invalid picker data", vim.log.levels.ERROR)
    return
  end

  if #items == 0 then
    vim.notify("There is nothing to pick. Start a session with `nsm new <name>`.", vim.log.levels.WARN)
    return
  end

  vim.ui.select(items, {
    prompt = "nsm> ",
    format_item = function(item) return item.label end,
  }, function(item)
    if item then on_choice(item) end
  end)
end

--- Attach the current UI to the Neovim server at `address`.
---
---@param address string
function nsm.connect(address)
  local ok, err = pcall(function() vim.cmd({ cmd = "connect", args = { address } }) end)
  if not ok then notify_error(err) end
end

--- Open the picker and switch the current UI to the chosen session.
---
--- Start the chosen session when it is stopped, then detach the current UI from
--- its server and attach it to the chosen server with `:connect`.
---
function nsm.switch()
  pick(function(item)
    if item.source == "host" and item.address then
      nsm.connect(item.address)
      return
    end

    run_async({ "nsm", "start", get_target(item) }, function(socket)
      if socket and socket ~= "" then nsm.connect(socket) end
    end)
  end)
end

--- Change the mapping of the plugin.
---
--- Leave the plugin defaults alone when `opts` is missing. Pass `keymap = false`
--- to remove the plugin mapping. A mapping that the user owns is never removed.
---
---@param opts nsm.Config|nil
function nsm.setup(opts)
  opts = opts or {}

  if opts.scope ~= nil then scope = opts.scope end

  local keymap = opts.keymap
  if keymap == nil then return end

  if mapped then
    vim.keymap.del("n", mapped)
    mapped = nil
  end

  if vim.fn.maparg("<leader>w", "n", false, true).rhs == "<Plug>(nsm-switch)" then vim.keymap.del("n", "<leader>w") end

  if keymap then
    vim.keymap.set("n", keymap, "<Plug>(nsm-switch)", { desc = "Switch session" })
    mapped = keymap
  end
end

return nsm
