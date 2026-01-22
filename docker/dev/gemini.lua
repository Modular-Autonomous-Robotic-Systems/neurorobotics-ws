-- lua/plugins/gemini.lua
return {
	{
		"gutsavgupta/nvim-gemini-companion",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"ibhagwan/fzf-lua", -- Required for the custom UI select integration
		},
		event = "VeryLazy",
		config = function()
			local gemini = require("gemini")

			-- 1. Enable Fzf Support
			-- Override vim.ui.select to use fzf-lua for a better selection experience
			vim.ui.select = function(items, opts, onChoice)
				require("fzf-lua").fzf_exec(items, {
					prompt = opts.prompt or "Select from items",
					actions = {
						["default"] = function(selected)
							onChoice(selected[1])
						end,
					},
					winopts = { height = math.min(0.2 + #items * 0.05, 0.6) },
				})
			end

			-- 2. Setup Gemini
			gemini.setup({
				-- We only specify "gemini" as qwen is not installed in the Dockerfile
				cmds = { "gemini" },
				win = {
					preset = "right-fixed", -- Default style: floating, right-fixed, left-fixed, bottom-fixed
					width = 0.8,
					height = 0.8,
				},
				-- Optional: Customize terminal mapping if needed
				on_buf = function(buf)
					-- Example: Add buffer-specific keys here if necessary
				end,
			})
		end,

		-- 3. Easy to Remember Keybindings (Prefix: <leader>g)
		keys = {
			-- Core Interface
			{ "<leader>gg", "<cmd>GeminiToggle<cr>", desc = "Gemini: Toggle Sidebar" },
			{ "<leader>gc", "<cmd>GeminiSwitchToCli<cr>", desc = "Gemini: Switch/Spawn Agent" },
			{ "<leader>gy", "<cmd>GeminiSwitchSidebarStyle<cr>", desc = "Gemini: Switch Sidebar Style" },

			-- Visual Selection Interaction
			{
				"<leader>gs",
				function()
					vim.cmd("normal! gv")
					vim.cmd("'<,'>GeminiSend")
				end,
				mode = { "x" },
				desc = "Gemini: Send Selection to AI",
			},

			-- Diagnostics & Debugging
			{ "<leader>gd", "<cmd>GeminiSendLineDiagnostic<cr>", desc = "Gemini: Explain Line Diagnostic" },
			{ "<leader>gD", "<cmd>GeminiSendFileDiagnostic<cr>", desc = "Gemini: Explain File Diagnostics" },

			-- Diff Management (Standard vim diff commands work, but these are explicit)
			{ "<leader>ga", "<cmd>GeminiAccept<cr>", desc = "Gemini: Accept Changes" },
			{ "<leader>gr", "<cmd>GeminiReject<cr>", desc = "Gemini: Reject Changes" },
		},
	},
}
