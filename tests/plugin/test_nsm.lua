local test = require("mini.test")
local eq = test.expect.equality

local child = test.new_child_neovim()

local prelude = [=[
  H = { calls = {}, notifications = {}, connects = {} }

  vim.notify = function(text, level) table.insert(H.notifications, { text = text, level = level }) end

  -- Pretend Neovim has `:connect ssh://` unless a case says otherwise.
  vim.fn.getcompletion = function() return { "remote-ssh" } end

  H.system = function(handler)
    vim.system = function(command, _, on_exit)
      table.insert(H.calls, command)
      local result = handler(command)
      result.wait = function(self) return self end
      if result.defer then
        H.pending = function() on_exit(result) end
      elseif on_exit then
        on_exit(result)
      end
      return result
    end
  end

  H.select = function(index)
    vim.ui.select = function(items, opts, on_choice)
      H.items = items
      H.prompt = opts.prompt
      on_choice(index and items[index] or nil, index)
    end
  end

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

local T = test.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/init.lua" }, { connection_timeout = 2000 })
      child.lua(prelude)
    end,
    post_once = child.stop,
  },
})

local rows = {
  session = '[{"label":"🟢 work  ~/work","name":"work","path":"/home/ana/work","source":"running"}]',
  directory = '[{"label":"📁 ~/project","name":null,"path":"/home/ana/project","source":"directory"}]',
  host = '[{"label":"🌐 work","name":null,"path":null,"source":"host","address":"ssh://work"}]',
  empty = "[]",
}

T["switch"] = test.new_set()

T["switch"]["starts the chosen session and attaches the current UI"] = function()
  local result = child.lua(([[
    local rows = %s
    H.system(function(command)
      return { code = 0, stdout = command[2] == "pick" and rows or "/state/nsm/work.sock\n", stderr = "" }
    end)
    H.select(1)

    H.load().switch()

    return H.flush().calls
  ]]):format(vim.inspect(rows.session)))

  eq(result, {
    { "nsm", "pick", "--hosts" },
    { "nsm", "start", "work" },
  })
  eq(child.lua_get("H.connects"), { "/state/nsm/work.sock" })
end

T["switch"]["starts a directory that has no session yet"] = function()
  local calls = child.lua(([[
    local rows = %s
    H.system(function(command)
      return { code = 0, stdout = command[2] == "pick" and rows or "/state/nsm/project.sock\n", stderr = "" }
    end)
    H.select(1)

    H.load().switch()

    return H.flush().calls
  ]]):format(vim.inspect(rows.directory)))

  eq(calls, {
    { "nsm", "pick", "--hosts" },
    { "nsm", "start", "/home/ana/project" },
  })
  eq(child.lua_get("H.connects"), { "/state/nsm/project.sock" })
end

T["switch"]["cancelling the picker starts and connects nothing"] = function()
  local result = child.lua(([[
    local rows = %s
    H.system(function()
      return { code = 0, stdout = rows, stderr = "" }
    end)
    H.select(nil)

    H.load().switch()
    H.flush()

    return { calls = H.calls, connects = H.connects, labels = H.items and H.items[1].label, prompt = H.prompt }
  ]]):format(vim.inspect(rows.session)))

  eq(result.calls, { { "nsm", "pick", "--hosts" } })
  eq(result.connects, {})
  eq(result.prompt, "nsm> ")
  eq(result.labels, "🟢 work  ~/work")
end

T["switch"]["notifies on invalid picker JSON"] = function()
  local notification = child.lua([[
    H.system(function() return { code = 0, stdout = "not json", stderr = "" } end)

    H.load().switch()

    return H.notifications[1]
  ]])

  eq(notification.text, "nsm returned invalid picker data")
  eq(notification.level, child.lua_get("vim.log.levels.ERROR"))
end

T["switch"]["notifies the stripped picker error"] = function()
  local message = child.lua([[
    H.system(function()
      return { code = 1, stdout = "", stderr = "\27[31m[E]\27[0m Cannot query the sessions\n" }
    end)

    H.load().switch()

    return H.notifications[1].text
  ]])

  eq(message, "[E] Cannot query the sessions")
end

T["start"] = test.new_set()

T["start"]["notifies the stripped start error and connects nothing"] = function()
  local result = child.lua(([[
    local rows = %s
    H.system(function(command)
      if command[2] == "pick" then return { code = 0, stdout = rows, stderr = "" } end
      return { code = 1, stdout = "", stderr = "\27[31m[E]\27[0m The server did not start\n" }
    end)
    H.select(1)

    H.load().switch()
    H.flush()

    return { text = H.notifications[1].text, connects = H.connects }
  ]]):format(vim.inspect(rows.session)))

  eq(result.text, "[E] The server did not start")
  eq(result.connects, {})
end

T["connect"] = test.new_set()

T["connect"]["attaches the UI to the address"] = function()
  local commands = child.lua([[
    local commands = {}
    vim.cmd = function(command) table.insert(commands, command) end

    require("nsm").connect("ssh://work")

    return commands
  ]])

  eq(commands, { { cmd = "connect", args = { "ssh://work" } } })
end

T["connect"]["notifies the stripped failure"] = function()
  local message = child.lua([[
    vim.cmd = function() error("\27[31m[E]\27[0m Failed to connect", 0) end

    require("nsm").connect("/nonexistent/nsm.sock")

    return H.notifications[1].text
  ]])

  eq(message, "[E] Failed to connect")
end

T["commands"] = test.new_set()

T["commands"]["register the user command and the plug mapping"] = function()
  local result = child.lua([[
    local switched = 0
    vim.cmd("runtime plugin/nsm.lua")

    local nsm = require("nsm")
    nsm.switch = function() switched = switched + 1 end

    vim.cmd({ cmd = "Nsm" })
    local mapping = vim.fn.maparg("<Plug>(nsm-switch)", "n", false, true)
    mapping.callback()

    return { switched = switched, desc = mapping.desc }
  ]])

  eq(result.switched, 2)
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

  local connects = child.lua(([[
    vim.env.NSM_ROWS = %q
    vim.env.NSM_SOCKET = "/state/nsm/work.sock\n"

    H.select(1)
    H.load().switch()
    vim.wait(2000, function() return #H.connects > 0 end, 10)

    return H.connects
  ]]):format(rows.session))

  eq(connects, { "/state/nsm/work.sock" })
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

T["health"]["reports every tool when they are installed"] = function()
  local reports = child.lua([[
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    for _, name in ipairs({ "nsm", "fzf", "zoxide" }) do
      local path = dir .. "/" .. name
      vim.fn.writefile({ "#!/usr/bin/env bash", "exit 0" }, path)
      vim.uv.fs_chmod(path, 493)
    end
    vim.env.PATH = dir .. ":" .. vim.env.PATH

    ]] .. health_prelude .. [[

    H.health.check()
    return H.reports
  ]])

  eq(reports[1], { "start", "nsm" })
  eq(reports[2][1], "ok")
  assert(reports[2][2]:find("nsm:") == 1)
  eq(reports[3], { "ok", "Neovim 0.12 :connect: available" })
  eq(reports[4], { "ok", ":connect ssh://: available" })
  eq(reports[5][1], "ok")
  eq(reports[6][1], "ok")
  eq(#reports, 6)
end

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
  eq(reports[4][1], "ok")
  eq(reports[5], { "warn", "fzf is not available" })
  eq(reports[6], { "warn", "zoxide is not available" })
end

T["health"]["warns without remote-ssh support"] = function()
  local reports = child.lua([[
    vim.env.PATH = ""
    vim.fn.getcompletion = function() return {} end

    ]] .. health_prelude .. [[

    H.health.check()
    return H.reports
  ]])

  eq(reports[4], { "warn", ":connect ssh:// is not available" })
end

T["setup"] = test.new_set()

T["setup"]["custom key replaces the default mapping"] = function()
  child.lua([[ require("nsm").setup({ keymap = "<leader>s" }) ]])

  eq(child.lua_get("vim.fn.maparg('<leader>w', 'n')"), "")
  eq(child.lua_get("vim.fn.maparg('<leader>s', 'n', false, true).rhs"), "<Plug>(nsm-switch)")
end

return T
