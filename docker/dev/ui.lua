-- lua/plugins/ui.lua
return {
	-- 1. Colorscheme (Essential for Syntax Highlighting)
	{
		"sainnhe/gruvbox-material",
		lazy = false, -- Load immediately during startup
		priority = 1000, -- Load before everything else
		config = function()
			-- Configuration options for gruvbox-material
			vim.g.gruvbox_material_enable_italic = 1
			vim.g.gruvbox_material_background = "medium" -- options: hard, medium, soft
			vim.g.gruvbox_material_better_performance = 1

			-- Set the colorscheme
			vim.cmd([[colorscheme gruvbox-material]])
			vim.api.nvim_set_hl(0, "Normal", { bg = "#000000" })
			vim.api.nvim_set_hl(0, "NormalFloat", { bg = "#000000" })
		end,
	},
	{
		"numToStr/Comment.nvim",
		event = "BufReadPre", -- Lazy-load
		opts = {
			-- Configuration options
			padding = true, -- Add a space after the comment delimiter
			sticky = true, -- Keep the cursor in place
			toggler = {
				line = "gcc", -- Line comment toggle
				block = "gbc", -- Block comment toggle
			},
			opleader = {
				line = "gc", -- Line comment operator
				block = "gb", -- Block comment operator
			},
		},
	},
	{
		"nvim-tree/nvim-web-devicons",
		lazy = true,
		opts = {}, -- Automatically runs require("nvim-web-devicons").setup()
	},
	-- 2. Bufferline (Shows open buffers at the top)
	{
		"akinsho/bufferline.nvim",
		version = "*",
		dependencies = "nvim-tree/nvim-web-devicons",
		event = "VeryLazy", -- Load after startup to not block UI
		config = function()
			require("bufferline").setup({
				options = {
					mode = "buffers", -- Show buffers, not tabs
					numbers = "none", -- "ordinal" | "buffer_id" | "both" | "none"
					diagnostics = "nvim_lsp", -- Show LSP errors in the tab
					separator_style = "thin", -- "slant" | "thick" | "thin" | { 'any', 'any' }
					show_buffer_close_icons = false,
					show_close_icon = false,
					always_show_bufferline = true,
					offsets = {
						{
							filetype = "NvimTree",
							text = "File Explorer",
							highlight = "Directory",
							text_align = "left",
						},
					},
				},
			})
			-- Keymaps for buffer navigation
			vim.keymap.set("n", "<S-h>", ":BufferLineCyclePrev<CR>", { desc = "Go to previous buffer" })
			vim.keymap.set("n", "<S-l>", ":BufferLineCycleNext<CR>", { desc = "Go to next buffer" })
			vim.keymap.set("n", "<leader>bp", ":BufferLinePick<CR>", { desc = "Pick buffer" })
			vim.keymap.set("n", "<leader>bc", ":bdelete<CR>", { desc = "Close current buffer" })
		end,
	},
	{
		"nvim-lualine/lualine.nvim",
		event = "BufReadPre",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		opts = {
			options = {
				icons_enabled = true,
				theme = "auto", -- Use the editor's colorscheme
				component_separators = { left = "[", right = "]" },
				section_separators = { left = " ", right = " " },
			},
			-- Configure sections to meet Requirement 8
			sections = {
				lualine_a = { "mode" }, -- Current nvim mode
				lualine_b = { "branch" }, -- Current git branch
				lualine_c = { "filename" }, -- File name
				lualine_x = { "filetype" }, -- File type
				lualine_y = { "progress" },
				lualine_z = { "location" }, -- Line/Character number
			},
			inactive_sections = {
				lualine_c = { "filename" },
				lualine_x = { "location" },
			},
		},
	},
	-- Clipboard Manager (OSC 52 for SSH/Docker)
	{
		"ojroques/nvim-osc52",
		config = function()
			-- Improved Environment Detection logic
			local is_ssh = os.getenv("SSH_TTY") or os.getenv("SSH_CONNECTION")
			local is_docker = vim.fn.filereadable("/.dockerenv") == 1
			local no_display = not os.getenv("DISPLAY") or os.getenv("DISPLAY") == ""

			if is_ssh or is_docker or no_display then
				local function copy(lines, _)
					require("osc52").copy(table.concat(lines, "\n"))
				end

				-- Note: OSC 52 usually cannot READ the clipboard for security reasons.
				-- For pasting in Docker/SSH, use your terminal's native paste (Ctrl+Shift+V or Cmd+V).
				local function paste()
					return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
				end

				vim.g.clipboard = {
					name = "osc52",
					copy = { ["+"] = copy, ["*"] = copy },
					paste = { ["+"] = paste, ["*"] = paste },
				}
			end
		end,
	},
}
