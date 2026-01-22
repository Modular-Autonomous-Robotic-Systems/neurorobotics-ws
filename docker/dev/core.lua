-- lua/plugins/core.lua
return {
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate", -- Automatically update parsers
		config = function()
			require("nvim-treesitter.configs").setup({
				-- Parsers for the user's languages
				ensure_installed = {
					"c",
					"cpp",
					"python",
					"java",
					"bash",
					"dockerfile",
					"lua", -- For configuring Neovim
					"markdown",
					"query",
					"vim",
					"vimdoc",
					"markdown_inline",
				},
				sync_install = true,
				auto_install = true, -- Automatically install missing parsers
				highlight = {
					enable = true, -- Enable syntax highlighting
					additional_vim_regex_highlighting = false,
				},
				indent = {
					enable = true, -- Enable indentation
				},
			})
		end,
	},
	-- File Explorer (Nvim-Tree)
	{
		"nvim-tree/nvim-tree.lua",
		version = "*",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			require("nvim-tree").setup({
				sort_by = "case_sensitive",
				view = { width = 30 },
				renderer = { group_empty = true },
				filters = { dotfiles = false },
			})
			vim.keymap.set('n', '<leader>e', ':NvimTreeToggle<CR>', { desc = 'Toggle File Explorer' })
		end,
	},
	{
		"ibhagwan/fzf-lua",
		-- lazy-load on command
		cmd = "FzfLua",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			require("fzf-lua").setup({
				-- Configuration for fzf-lua
				winopts = {
					-- Use a more modern border style
					border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
				},
				-- Setup for file and grep actions
				files = {
					prompt = "Files❯ ",
				},
				grep = {
					prompt = "Grep❯ ",
					rg_opts = "--hidden --column --line-number --no-heading --color=always --smart-case",
				},
				lsp = {
					prompt = "LSP❯ ",
				},
			})

			-- Keymaps
			-- Find files
			vim.keymap.set("n", "<leader>ff", "<cmd>FzfLua files<CR>", { desc = "Find files" })
			-- Search text in files (Live Grep)
			vim.keymap.set("n", "<leader>fg", "<cmd>FzfLua live_grep<CR>", { desc = "Find in files (Grep)" })
			-- Search symbols
			vim.keymap.set("n", "<leader>fs", "<cmd>FzfLua lsp_document_symbols<CR>", { desc = "Find symbols" })
		end,
	}
}
