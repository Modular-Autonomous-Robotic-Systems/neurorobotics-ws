-- =============================================================================
--  Neovim Configuration for Robotics Development (C++, Python, Java, Bash)
-- =============================================================================

-- 1. Core Options
vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]], { desc = "Copy to system clipboard" })
vim.keymap.set("n", "<leader>Y", [["+Y]], { desc = "Copy line to system clipboard" })
vim.keymap.set({ "n", "v" }, "<leader>p", [["+p]], { desc = "Paste from system clipboard" })
vim.keymap.set("n", "<leader>P", [["+P]], { desc = "Paste before from system clipboard" })

vim.opt.number = true -- Show line numbers
vim.opt.mouse = "a" -- Enable mouse support
vim.opt.clipboard = "unnamedplus" -- Sync with system clipboard
vim.opt.breakindent = true -- Maintain indent on wrapped lines
vim.opt.undofile = true -- Save undo history
vim.opt.ignorecase = true -- Case insensitive searching
vim.opt.smartcase = true -- ...unless capital letter used
vim.opt.signcolumn = "yes" -- Keep sign column on (prevents text shifting)
vim.opt.updatetime = 250 -- Faster updates
vim.opt.timeoutlen = 300 -- Faster mapped sequence wait time
vim.opt.splitright = true -- Split vertical windows to the right
vim.opt.splitbelow = true -- Split horizontal windows to the bottom
vim.opt.list = true -- Show some invisible characters
vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
vim.opt.termguicolors = true
-- Indentation Settings (Tab = 4 Spaces)
vim.opt.tabstop = 4 -- Number of spaces that a <Tab> in the file counts for
vim.opt.shiftwidth = 4 -- Number of spaces to use for each step of (auto)indent
vim.opt.expandtab = true -- Use spaces instead of tabs
vim.opt.softtabstop = 4 -- Number of spaces that a <Tab> counts for while editing

-- =============================================================================
-- 2. Plugin Manager (Lazy.nvim) Bootstrap
-- =============================================================================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

-- Load all plugin specifications from lua/plugins/
require("lazy").setup("plugins", {
	checker = {
		enabled = true,
		notify = false, -- Do not notify on new updates
	},
	change_detection = {
		notify = false, -- Do not notify on config change
	},
})
