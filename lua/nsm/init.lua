--- *nsm.nvim* Neovim Server Manager
---
--- Open the session picker for the detached Neovim servers that nsm keeps.
---
--- `:Nsm` and the `<Plug>(nsm-switch)` mapping switch the current UI to the
--- chosen session with `:connect`. `:Nsm kill` stops a chosen session, and
--- `:Nsm new` starts one for a directory.
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
--- to limit the picker to one directory. `nsm kill` refuses unsaved buffers.
--- Pass `--force` to override it. `:detach` keeps the server running.
---
--- Configuration ~
--- *nsm-configuration*
---
--- Create `~/.config/.nsm.nuon`:
---
--- >
---   {
---     projects: ["~/Projects", "/mnt/external/projects"]
---     icons: { running: "🟢", busy: "🟡", stored: "⚫", directory: "📁" }
---     restore: { file: "Session.vim" }
---   }
--- <
---
--- `projects` lists all project roots. Omit it to disable repository discovery.
--- `PROJECTS_DIR` is not read. `restore.file` is optional and runs project
--- Vimscript, so enable it only for trusted projects.
---
--- Remote use ~
--- *nsm-remote*
---
--- For SSH hosts, use `:connect ssh://<host>`. Neovim lists the hosts of
--- `~/.ssh/config` in its own menu, installs its own `nvim` on the host, and
--- copies your config there. To switch projects on that host, install `nsm`
--- with `fzf` and `git` there, then run `:Nsm` inside the remote session.
---
--- Picker rows ~
--- *nsm-rows*
---
--- `nsm pick` prints one JSON object per row. The fields are:
---
--- - `label`: the text that the picker shows.
--- - `name`: the session name, or null for a directory.
--- - `path`: the directory.
--- - `source`: `running`, `busy`, `stored`, `directory`, or `zoxide`.
---
--- Requirements ~
--- *nsm-requirements*
---
--- - Linux on x86_64 and Neovim 0.12+
--- - `nsm` on `PATH`: the Nix package and the AppImage bundle Nushell, `fzf`, `setsid`, and `timeout`
--- - `git` on `PATH` to name a session after its repository root
--- - `zoxide` on `PATH` for recent directories
---
---@tag nsm
---@tag :Nsm
---@tag :Nsm-kill
---@tag :Nsm-new
---@tag <Plug>(nsm-switch)
---@tag <Plug>(nsm-kill)
---@tag <Plug>(nsm-new)

---@class nsm.Config
---@field keymap string|false|nil Keymap for the session picker. Defaults to "<leader>w". Use false for no mapping.
---@field scope string|nil Only list rows under this directory.

local nsm = {}
local mapped
local scope

local cli = require("nsm.cli")

local UNSAVED = cli.UNSAVED

--- Return the name of the row, or its path when it has no session.
---
---@param item table
---@return string
---@private
local function get_target(item)
  if item.name and item.name ~= vim.NIL and item.name ~= "" then return item.name end
  return item.path
end

---@class nsm.PickOptions
---@field sessions boolean|nil Only list sessions.

--- Ask for a row with `vim.ui.select`.
---
---@param opts nsm.PickOptions
---@param on_choice fun(item: table)
---@private
local function pick(opts, on_choice)
  local command = { "nsm", "pick" }
  if opts.sessions then table.insert(command, "--sessions") end
  if scope and scope ~= "" then vim.list_extend(command, { "--scope", scope }) end

  cli.run(command, function(output)
    local ok, items = pcall(vim.json.decode, output)
    if not ok or type(items) ~= "table" then
      vim.notify("nsm returned invalid picker data", vim.log.levels.ERROR)
      return
    end

    if #items == 0 then
      local message = opts.sessions and "There are no sessions." or "There is nothing to pick. Start a session with `nsm new <name>`."
      vim.notify(message, vim.log.levels.WARN)
      return
    end

    vim.ui.select(items, {
      prompt = "nsm> ",
      format_item = function(item) return item.label end,
    }, function(item)
      if item then on_choice(item) end
    end)
  end)
end

--- Attach the current UI to the Neovim server at `address`.
---
---@param address string
function nsm.connect(address)
  local ok, err = pcall(function() vim.cmd({ cmd = "connect", args = { address } }) end)
  if not ok then cli.notify_error(err) end
end

--- Start a session and attach the current UI to its socket.
---
---@param target string
---@private
local function start_and_connect(target)
  cli.run({ "nsm", "start", target }, function(socket)
    if socket and socket ~= "" then nsm.connect(socket) end
  end)
end

--- Notify the output of a command when it has any.
---
---@param stdout string
---@private
local function notify_output(stdout)
  if stdout ~= "" then vim.notify(stdout) end
end

--- Open the picker and switch the current UI to the chosen session.
---
--- Start the chosen session when it is stopped, then detach the current UI from
--- its server and attach it to the chosen server with `:connect`.
---
function nsm.switch()
  pick({}, function(item) start_and_connect(get_target(item)) end)
end

--- Pick a session and stop it, with a force stop when it has unsaved changes.
---
--- `nsm kill` exits with code 3 when it refuses the session, so the plugin can
--- offer a force stop.
---
function nsm.kill()
  pick({ sessions = true }, function(item)
    local target = get_target(item)
    local command = { "nsm", "kill", target }

    cli.run(command, notify_output, function(result)
      if result.code ~= UNSAVED then
        cli.notify_error(cli.get_message(command, result))
        return
      end

      vim.ui.select({ "Force stop", "Cancel" }, { prompt = cli.get_message(command, result) }, function(choice)
        if choice == "Force stop" then cli.run({ "nsm", "kill", "--force", target }, notify_output) end
      end)
    end)
  end)
end

--- Ask for a directory, then start a session for it and attach the current UI.
---
function nsm.new()
  vim.ui.input({ prompt = "nsm directory> ", default = vim.fn.getcwd(), completion = "dir" }, function(input)
    if not input or input == "" then return end

    start_and_connect(vim.fs.normalize(vim.fn.fnamemodify(input, ":p")))
  end)
end

-- Each name is also a function of the plugin.
local subcommands = { "kill", "new" } ---@type string[]

--- Run a `:Nsm` subcommand by name, or switch when the name is empty.
---
---@param name string
function nsm.command(name)
  if name == "" then
    nsm.switch()
  elseif vim.tbl_contains(subcommands, name) then
    nsm[name]()
  else
    vim.notify("Unknown subcommand: " .. name, vim.log.levels.ERROR)
  end
end

--- Return the subcommands of `:Nsm`, for the command completion.
---
---@return string[]
function nsm.complete() return vim.deepcopy(subcommands) end

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
