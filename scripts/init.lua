vim.opt.runtimepath:append(vim.uv.cwd())

local mini = vim.env.MINI_NVIM

if not mini then error("MINI_NVIM is not set. Run this config through `devenv test`.") end

vim.opt.runtimepath:append(mini)

require("mini.test").setup()
require("mini.doc").setup()
