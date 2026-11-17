--- *nsm.nvim* Neovim Server Manager
---
--- Keep one detached Neovim server per project. The picker switches the current
--- UI to a session with `:connect`, so the terminal keeps its window.
---
--- Neovim commands ~
--- *nsm-commands*
---
--- - `:Nsm`: pick a session and switch to it.
--- - `:Nsm new`: start a session for a directory.
--- - `:Nsm kill`: stop a chosen session.
---
--- The plugin also sets `<Plug>(nsm-switch)`, `<Plug>(nsm-kill)`, and
--- `<Plug>(nsm-new)`. The command `:detach` keeps the server running.
---
--- The picker opens from the rows of its previous call and refreshes them in
--- the background. The first call, and the first call after a session starts or
--- stops, wait for `nsm pick`.
---
--- Setup ~
--- *nsm-setup*
---
--- >lua
---   require("nsm").setup({ keymap = "<leader>w", scope = "~/Projects" })
--- <
---
--- - `keymap`: the key that runs `<Plug>(nsm-switch)`. There is no key by
---   default. Use `false` to remove the key.
--- - `scope`: only list rows under this directory. The variable `NSM_SCOPE`
---   does the same.
---
--- Terminal commands ~
--- *nsm-terminal*
---
--- - `nsm attach [name-or-directory]`: create or open a session, or pick one.
--- - `nsm switch`: pick another session.
--- - `nsm last`: return to the previous session.
--- - `nsm new <name> [path]`: create a named session.
--- - `nsm start <name-or-directory>`: start a session and print its socket.
--- - `nsm list`: print the sessions and their status.
--- - `nsm pick`: print the picker rows as JSON.
--- - `nsm kill [name]`: stop a session, or every session with `--all`.
--- - `nsm a`, `nsm s`, `nsm l`, `nsm n`, `nsm ls`, `nsm k`: short forms.
---
--- Pass `--scope <path>` to `attach`, `switch`, or `kill` to limit the picker
--- to one directory.
---
--- Session status ~
--- *nsm-status*
---
--- - `active`: the server runs. It is busy when it is slow to answer, for
---   example while Neovim runs a long task.
--- - `inactive`: the server is stopped. `nsm attach` starts it again.
---
--- `nsm kill` refuses a session with unsaved buffers, and a server that does
--- not answer. Both refusals use exit code 3. Pass `--force` to stop the session
--- anyway. `--force` ends a server that does not answer with a signal.
---
--- Configuration ~
--- *nsm-configuration*
---
--- Create `~/.config/.nsm.nuon`. Every key is optional.
---
--- >
---   {
---     projects: ["~/Projects", "/mnt/external/projects"]
---     icons: { running: "🟢", busy: "🟡", stored: "⚫", directory: "📁" }
---     restore: { file: "Session.vim" }
---   }
--- <
---
--- - `projects`: the directories that hold your projects. The picker lists the
---   git repositories up to four levels below them. Omit it for no repositories.
--- - `icons`: the icon of each `source` in |nsm-rows|.
--- - `restore.file`: a Vimscript file, relative to the project, that a new
---   server runs. It runs project code, so enable it only for trusted projects.
---
--- Picker rows ~
--- *nsm-rows*
---
--- `nsm pick` prints one JSON object per row. The fields are:
---
--- - `label`: the text that the picker shows.
--- - `name`: the session name, or null for a directory.
--- - `path`: the directory.
--- - `source`: where the row comes from.
---
--- The values of `source` are:
---
--- - `running`: a session whose server answers.
--- - `busy`: a session whose server is slow to answer.
--- - `stored`: a session whose server is stopped.
--- - `directory`: a git repository below a project root.
--- - `zoxide`: a recent directory that zoxide knows.
---
--- Remote use ~
--- *nsm-remote*
---
--- For SSH hosts, use `:connect ssh://<host>`. Neovim lists the hosts of
--- `~/.ssh/config` in its own menu, installs its own `nvim` on the host, and
--- copies your config there. To switch projects on that host, install `nsm`
--- with `fzf` and `git` there, then run `:Nsm` inside the remote session.
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
---@field keymap string|false|nil Key that runs `<Plug>(nsm-switch)`. There is no key by default. Use false to remove it.
---@field scope string|nil Only list rows under this directory.

local nsm = {}
local mapped
local scope
local cache = {} ---@type table<string, table[]>
local generation = 0

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

--- Forget the cached picker rows, because a session started or stopped.
---
---@private
local function clear_cache()
  cache = {}
  generation = generation + 1
end

--- Ask `vim.ui.select` for a row.
---
---@param items table[]
---@param on_choice fun(item: table)
---@param opts nsm.PickOptions
---@private
local function select_row(items, on_choice, opts)
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
end

--- Ask for a row with `vim.ui.select`.
---
--- Open the picker at once from the rows of the previous call, and refresh
--- the rows in the background. Wait for `nsm pick` when there are no rows yet.
---
---@param opts nsm.PickOptions
---@param on_choice fun(item: table)
---@private
local function pick(opts, on_choice)
  local command = { "nsm", "pick" }
  if opts.sessions then table.insert(command, "--sessions") end
  if scope and scope ~= "" then vim.list_extend(command, { "--scope", scope }) end

  local key = table.concat(command, " ")
  local cached = cache[key]
  local started = generation

  if cached then select_row(cached, on_choice, opts) end

  cli.run(command, function(output)
    local ok, items = pcall(vim.json.decode, output)
    if not ok or type(items) ~= "table" then
      vim.notify("nsm returned invalid picker data", vim.log.levels.ERROR)
      return
    end

    if started == generation and #items > 0 then cache[key] = items end
    if not cached then select_row(items, on_choice, opts) end
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
    clear_cache()
    if socket and socket ~= "" then nsm.connect(socket) end
  end)
end

--- Forget the cached rows, then show the output of `nsm kill` when it has any.
---
---@param stdout string
---@private
local function notify_output(stdout)
  clear_cache()
  if stdout ~= "" then vim.notify(stdout) end
end

--- Pick a session, start it when it is stopped, and attach the current UI to it
--- with `:connect`.
---
function nsm.switch()
  pick({}, function(item) start_and_connect(get_target(item)) end)
end

--- Pick a session and stop it.
---
--- `nsm kill` refuses a session with unsaved buffers, and a server that does not
--- answer. The plugin then offers a force stop.
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

-- Each subcommand is also a function of the plugin.
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

--- Set the key and the scope of the plugin.
---
--- Leave the defaults alone when `opts` is missing. Pass `keymap = false` to
--- remove the key of the plugin. A key that you own stays.
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
