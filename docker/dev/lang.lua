-- lua/plugins/lang.lua
return {
	{
		"stevearc/conform.nvim",
		event = "BufWritePre", -- Run formatter before saving
		cmd = "ConformInfo",
		opts = {
			-- Enable format on save
			format_on_save = {
				timeout_ms = 500,
				lsp_format = "fallback", -- Fallback to LSP formatting if conform fails
			},
			-- Define formatters for each file type
			formatters_by_ft = {
				lua = { "stylua" },
				-- Run isort then black sequentially
				python = { "isort", "black" },
				c = { "clang_format" },
				cpp = { "clang_format" },
				java = { "clang_format" }, -- Can also use LSP
				bash = { "shfmt" },
				dockerfile = { "dockerfile-language-server" }, -- Use LSP formatter
			},
		},
	},
	{
		"mfussenegger/nvim-lint",
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			local lint = require("lint")
			-- Configure linters
			lint.linters_by_ft = {
				python = { "ruff" }, -- ruff is a popular, fast linter
				bash = { "shellcheck" },
			}
			-- Enable linting on text change and save
			vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
				group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
				callback = function()
					lint.try_lint()
				end,
			})
		end,
	},
	--... nvim-jdtls plugin will go here
}
