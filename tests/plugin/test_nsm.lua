local test = require("mini.test")
local eq = test.expect.equality

local child = test.new_child_neovim()

local prelude = [=[
  H = { calls = {}, notifications = {}, connects = {} }

  vim.notify = function(text, level) table.insert(H.notifications, { text = text, level = level }) end

  H.system = function(handler)
    vim.system = function(command, opts, on_exit)
      table.insert(H.calls, command)
      local result = handler(command)
      result.wait = function(self) return self end
      if opts and opts.stderr then
        for _, chunk in ipairs(result.chunks or { result.stderr or "" }) do
          if chunk ~= "" then opts.stderr(nil, chunk) end
        end
        result.stderr = nil
      end
      if result.defer then
        H.pending = function() on_exit(result) end
      elseif on_exit then
        on_exit(result)
      end
      return result
    end
  end

  H.select = function(...)
    H.selects = H.selects or {}
    for _, index in ipairs({ ... }) do
      table.insert(H.selects, index or false)
    end
    vim.ui.select = function(items, opts, on_choice)
      H.items = items
      H.prompt = opts.prompt
      local index = table.remove(H.selects, 1)
      on_choice(index and items[index] or nil, index)
    end
  end

  H.input = function(value)
    vim.ui.input = function(opts, on_confirm)
      H.input_opts = opts
      on_confirm(value)
    end
  end

  H.texts = function() return vim.tbl_map(function(entry) return entry.text end, H.notifications) end

  H.load = function()
    package.loaded["nsm"] = nil
    local nsm = require("nsm")
    nsm.connect = function(address) table.insert(H.connects, address) end
    return nsm
  end

  -- Wait for scheduled callbacks so that missing actions are observable.
  H.flush = function()
    local done = false
    vim.schedule(function() done = true end)
    vim.wait(1000, function() return done end, 10)
    return H
  end
]=]

local rows = {
  session = '[{"label":"🟢 work  ~/work","name":"work","path":"/home/ana/work","source":"running"}]',
  directory = '[{"label":"📁 ~/project","name":null,"path":"/home/ana/project","source":"directory"}]',
}

local T = test.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/init.lua" }, { connection_timeout = 2000 })
      child.lua(prelude)
      child.lua("H.rows = ...", { rows })
    end,
    post_once = child.stop,
  },
})

T["switch"] = test.new_set()

T["switch"]["starts the chosen session and attaches the current UI"] = function()
  local result = child.lua([[
    H.system(function(command)
      return { code = 0, stdout = command[2] == "pick" and H.rows.session or "/state/nsm/work.sock\n", stderr = "" }
    end)
    H.select(1)

    H.load().switch()

    return H.flush().calls
  ]])

  eq(result, {
    { "nsm", "pick" },
    { "nsm", "start", "work" },
  })
  eq(child.lua_get("H.connects"), { "/state/nsm/work.sock" })
end

T["switch"]["returns before the picker rows arrive"] = function()
  local result = child.lua([[
    H.system(function(command)
      if command[2] == "pick" then return { code = 0, stdout = H.rows.session, stderr = "", defer = true } end
      return { code = 0, stdout = "/state/nsm/work.sock\n", stderr = "" }
    end)
    H.select(1)

    H.load().switch()

    local before = { selected = H.items ~= nil, connects = #H.connects }
    H.pending()
    H.flush()

    return { before = before, labels = { H.items[1].label }, connects = H.connects }
  ]])

  eq(result.before, { selected = false, connects = 0 })
  eq(result.labels, { "🟢 work  ~/work" })
  eq(result.connects, { "/state/nsm/work.sock" })
end

T["switch"]["starts a directory that has no session yet"] = function()
  local calls = child.lua([[
    H.system(function(command)
      return { code = 0, stdout = command[2] == "pick" and H.rows.directory or "/state/nsm/project.sock\n", stderr = "" }
    end)
    H.select(1)

    H.load().switch()

    return H.flush().calls
  ]])

  eq(calls, {
    { "nsm", "pick" },
    { "nsm", "start", "/home/ana/project" },
  })
  eq(child.lua_get("H.connects"), { "/state/nsm/project.sock" })
end

T["switch"]["cancelling the picker starts and connects nothing"] = function()
  local result = child.lua([[
    H.system(function()
      return { code = 0, stdout = H.rows.session, stderr = "" }
    end)
    H.select(nil)

    H.load().switch()
    H.flush()

    return { calls = H.calls, connects = H.connects, labels = H.items and H.items[1].label, prompt = H.prompt }
  ]])

  eq(result.calls, { { "nsm", "pick" } })
  eq(result.connects, {})
  eq(result.prompt, "nsm> ")
  eq(result.labels, "🟢 work  ~/work")
end

T["start"] = test.new_set()

T["start"]["notifies the stripped start error and connects nothing"] = function()
  local result = child.lua([[
    H.system(function(command)
      if command[2] == "pick" then return { code = 0, stdout = H.rows.session, stderr = "" } end
      return { code = 1, stdout = "", stderr = "\27[31m[E]\27[0m The server did not start\n" }
    end)
    H.select(1)

    H.load().switch()
    H.flush()

    return { text = H.notifications[1].text, connects = H.connects }
  ]])

  eq(result.text, "[E] The server did not start")
  eq(result.connects, {})
end

T["connect"] = test.new_set()

T["connect"]["attaches the UI to the address"] = function()
  local commands = child.lua([[
    local commands = {}
    vim.cmd = function(command) table.insert(commands, command) end

    require("nsm").connect("/state/nsm/work.sock")

    return commands
  ]])

  eq(commands, { { cmd = "connect", args = { "/state/nsm/work.sock" } } })
end

T["kill"] = test.new_set()

T["kill"]["stops the chosen session"] = function()
  local result = child.lua([[
    H.system(function(command)
      if command[2] == "pick" then return { code = 0, stdout = H.rows.session, stderr = "" } end
      return { code = 0, stdout = "Stopped work.\n", stderr = "" }
    end)
    H.select(1)

    H.load().kill()
    H.flush()

    return { calls = H.calls, notifications = vim.tbl_map(function(entry) return entry.text end, H.notifications) }
  ]])

  eq(result.calls, {
    { "nsm", "pick", "--sessions" },
    { "nsm", "kill", "work" },
  })
  eq(result.notifications, { "Stopped work." })
end

T["kill"]["offers a force stop for unsaved changes"] = function()
  local result = child.lua([[
    H.system(function(command)
      if command[2] == "pick" then return { code = 0, stdout = H.rows.session, stderr = "" } end
      if command[3] == "--force" then return { code = 0, stdout = "Stopped work.\n", stderr = "" } end
      return { code = 3, stdout = "", stderr = "\27[31m[E]\27[0m The session (work) has unsaved changes.\n" }
    end)
    H.select(1, 1)

    H.load().kill()
    H.flush()

    return { calls = H.calls, prompt = H.prompt, notifications = vim.tbl_map(function(entry) return entry.text end, H.notifications) }
  ]])

  eq(result.calls, {
    { "nsm", "pick", "--sessions" },
    { "nsm", "kill", "work" },
    { "nsm", "kill", "--force", "work" },
  })
  eq(result.prompt, "[E] The session (work) has unsaved changes.")
  eq(result.notifications, { "Stopped work." })
end

T["progress"] = test.new_set()

T["progress"]["shows the lines of a slow start after 100 ms"] = function()
  local result = child.lua([[
    local nsm = H.load()
    vim.ui.input = function(_, on_confirm) on_confirm("/tmp") end

    H.system(function()
      return {
        code = 0,
        stdout = "/state/nsm/slow.sock\n",
        chunks = { "Starting work…\n", "Loading the environment of work with direnv…\n" },
        defer = true,
      }
    end)
    nsm.new()
    vim.wait(30)
    local early = vim.deepcopy(H.texts())
    vim.wait(150)
    local slow = vim.deepcopy(H.texts())
    H.pending()
    H.flush()

    return { early = early, slow = slow, connects = H.connects }
  ]])

  eq(result.early, {})
  eq(result.slow, { "Starting work…", "Loading the environment of work with direnv…" })
  eq(result.connects, { "/state/nsm/slow.sock" })
end

T["progress"]["shows nothing for a fast start"] = function()
  local result = child.lua([[
    local nsm = H.load()
    vim.ui.input = function(_, on_confirm) on_confirm("/tmp") end

    H.system(function() return { code = 0, stdout = "/state/nsm/fast.sock\n", chunks = { "Starting work…\n" } } end)
    nsm.new()
    vim.wait(150)

    return { texts = H.texts(), connects = H.connects }
  ]])

  eq(result.texts, {})
  eq(result.connects, { "/state/nsm/fast.sock" })
end

T["last"] = test.new_set()

T["last"]["connects to the socket of the previous session"] = function()
  local result = child.lua([[
    H.system(function() return { code = 0, stdout = "/state/nsm/old.sock\n", stderr = "" } end)

    H.load().last()

    return H.flush().calls
  ]])

  eq(result, { { "nsm", "last", "--print" } })
  eq(child.lua_get("H.connects"), { "/state/nsm/old.sock" })
end

T["current"] = test.new_set()

T["current"]["returns the session name, or nil outside a session"] = function()
  local result = child.lua([[
    local nsm = H.load()
    local cases = {}

    vim.env.NSM_SESSION = "work"
    cases.set = nsm.current()
    vim.env.NSM_SESSION = ""
    cases.empty = nsm.current() == nil
    vim.env.NSM_SESSION = nil
    cases.unset = nsm.current() == nil

    return cases
  ]])

  eq(result, { set = "work", empty = true, unset = true })
end

T["new"] = test.new_set()

T["new"]["starts and connects to the chosen directory"] = function()
  local result = child.lua([[
    H.system(function()
      return { code = 0, stdout = "/state/nsm/project.sock\n", stderr = "" }
    end)
    H.input("/home/ana/project")

    H.load().new()
    H.flush()

    return { calls = H.calls, opts = H.input_opts, connects = H.connects }
  ]])

  eq(result.calls, { { "nsm", "start", "/home/ana/project" } })
  eq(result.connects, { "/state/nsm/project.sock" })
  eq(result.opts.prompt, "nsm directory> ")
  eq(result.opts.completion, "dir")
  assert(type(result.opts.default) == "string" and result.opts.default ~= "")
end

T["commands"] = test.new_set()

T["commands"]["register the user command and the plug mappings"] = function()
  local result = child.lua([[
    vim.cmd("runtime plugin/nsm.lua")

    local calls = {}
    local nsm = require("nsm")
    nsm.switch = function() table.insert(calls, "switch") end
    nsm.last = function() table.insert(calls, "last") end
    nsm.kill = function() table.insert(calls, "kill") end
    nsm.new = function() table.insert(calls, "new") end

    vim.cmd({ cmd = "Nsm" })
    vim.cmd({ cmd = "Nsm", args = { "last" } })
    vim.cmd({ cmd = "Nsm", args = { "kill" } })
    vim.cmd({ cmd = "Nsm", args = { "new" } })
    for _, name in ipairs({ "switch", "last", "kill", "new" }) do
      vim.fn.maparg("<Plug>(nsm-" .. name .. ")", "n", false, true).callback()
    end

    return {
      calls = calls,
      complete = nsm.complete(""),
      filtered = nsm.complete("k"),
      none = nsm.complete("x"),
      desc = vim.fn.maparg("<Plug>(nsm-switch)", "n", false, true).desc,
    }
  ]])

  eq(result.calls, { "switch", "last", "kill", "new", "switch", "last", "kill", "new" })
  eq(result.complete, { "kill", "last", "new" })
  eq(result.filtered, { "kill" })
  eq(result.none, {})
  eq(result.desc, "Switch session")
end

T["integration"] = test.new_set()

local function write_nsm(dir, bash)
  local script = table.concat({
    "#!" .. bash,
    'if [ "$1" = "pick" ]; then printf "%s" "$NSM_ROWS"; exit 0; fi',
    'if [ "$1" = "start" ]; then printf "%s\\n" "$NSM_SOCKET"; exit 0; fi',
    "exit 1",
  }, "\n")

  child.lua(
    [[
      local dir, script = ...
      local path = dir .. "/nsm"
      vim.fn.writefile(vim.split(script, "\n"), path)
      vim.uv.fs_chmod(path, 493)
    ]],
    { dir, script }
  )
end

T["integration"]["uses the real CLI output"] = function()
  local dir = child.lua_get("(function() local path = vim.fn.tempname(); vim.fn.mkdir(path, 'p'); return path end)()")
  write_nsm(dir, child.lua_get("vim.fn.exepath('bash')"))
  child.lua("vim.env.PATH = ... .. ':' .. vim.env.PATH", { dir })

  local connects = child.lua([[
    vim.env.NSM_ROWS = H.rows.session
    vim.env.NSM_SOCKET = "/state/nsm/work.sock\n"

    H.select(1)
    H.load().switch()
    vim.wait(2000, function() return #H.connects > 0 end, 10)

    return H.connects
  ]])

  eq(connects, { "/state/nsm/work.sock" })
end

T["integration"]["stops a session through the real CLI"] = function()
  local dir = child.lua_get("(function() local path = vim.fn.tempname(); vim.fn.mkdir(path, 'p'); return path end)()")
  local script = table.concat({
    "#!" .. child.lua_get("vim.fn.exepath('bash')"),
    'if [ "$1" = "pick" ]; then printf "%s" "$NSM_ROWS"; exit 0; fi',
    'if [ "$1" = "kill" ] && [ "$2" != "--force" ] && [ -z "$NSM_FORCED" ]; then',
    '  printf "[E] The session (work) has unsaved changes.\n" >&2',
    "  exit 3",
    "fi",
    'printf "Stopped work.\n"',
  }, "\n")
  child.lua(
    [[
      local dir, script = ...
      local path = dir .. "/nsm"
      vim.fn.writefile(vim.split(script, "\n"), path)
      vim.uv.fs_chmod(path, 493)
    ]],
    { dir, script }
  )
  child.lua("vim.env.PATH = ... .. ':' .. vim.env.PATH", { dir })

  local result = child.lua([[
    vim.env.NSM_ROWS = H.rows.session
    H.select(1, 1)

    H.load().kill()
    vim.wait(2000, function() return #H.notifications > 0 end, 10)

    return { prompt = H.prompt, notifications = H.texts() }
  ]])

  eq(result.prompt, "[E] The session (work) has unsaved changes.")
  eq(result.notifications, { "Stopped work." })
end

T["health"] = test.new_set()

local health_prelude = [=[
  H.reports = {}
  vim.health = {
    start = function(message) table.insert(H.reports, { "start", message }) end,
    ok = function(message) table.insert(H.reports, { "ok", message }) end,
    warn = function(message) table.insert(H.reports, { "warn", message }) end,
    error = function(message) table.insert(H.reports, { "error", message }) end,
  }
  package.loaded["nsm.health"] = nil
  H.health = require("nsm.health")
]=]

T["health"]["reports missing tools with hints"] = function()
  local reports = child.lua([[
    vim.env.PATH = ""

    ]] .. health_prelude .. [[

    H.health.check()
    return H.reports
  ]])

  eq(reports[1], { "start", "nsm" })
  eq(reports[2][1], "error")
  assert(reports[2][2]:find("nsm is not available") == 1)
  eq(reports[3][1], "ok")
  eq(reports[4], { "error", "bash is not available" })
  eq(reports[5], { "warn", "git is not available" })
  eq(reports[6], { "warn", "zoxide is not available" })
end

T["setup"] = test.new_set()

T["setup"]["a new key replaces the previous key"] = function()
  child.lua([[
    require("nsm").setup({ keymap = "<leader>w" })
    require("nsm").setup({ keymap = "<leader>s" })
  ]])

  eq(child.lua_get("vim.fn.maparg('<leader>w', 'n')"), "")
  eq(child.lua_get("vim.fn.maparg('<leader>s', 'n', false, true).rhs"), "<Plug>(nsm-switch)")
end

return T
