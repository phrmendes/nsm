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
--- Requirements ~
--- *nsm-requirements*
---
--- - Neovim 0.12+
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

--- Run a command and return its trimmed stdout, or notify its failure.
---
---@param command string[]
---@return string|nil
---@private
local function run(command)
  local ok, result = pcall(function() return vim.system(command, { text = true }):wait() end)

  if not ok then
    vim.notify(strip_ansi(tostring(result)), vim.log.levels.ERROR)
    return nil
  end

  local stderr = (result.stderr or ""):gsub("%s+$", "")

  if result.code ~= 0 then
    local fallback = "`" .. table.concat(command, " ") .. "` failed"
    vim.notify(strip_ansi(stderr ~= "" and stderr or fallback), vim.log.levels.ERROR)
    return nil
  end

  return ((result.stdout or ""):gsub("%s+$", ""))
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

--- Ask for a session or directory with `vim.ui.select`.
---
---@param on_choice fun(item: table)
---@private
local function pick(on_choice)
  local command = { "nsm", "pick" }
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
  if not ok then vim.notify(strip_ansi(tostring(err)), vim.log.levels.ERROR) end
end

--- Open the picker and switch the current UI to the chosen session.
---
--- Start the chosen session when it is stopped, then detach the current UI from
--- its server and attach it to the chosen server with `:connect`.
function nsm.switch()
  pick(function(item)
    local socket = run({ "nsm", "start", get_target(item) })
    if socket and socket ~= "" then nsm.connect(socket) end
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
