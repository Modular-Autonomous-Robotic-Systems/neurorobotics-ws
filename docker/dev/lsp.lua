-- lua/plugins/lsp.lua
return {
	{
		"williamboman/mason.nvim",
		cmd = "Mason",
		opts = {},
	},
	{
		"williamboman/mason-lspconfig.nvim",
		-- This plugin is the bridge
		dependencies = {
			"williamboman/mason.nvim",
			"neovim/nvim-lspconfig",
		},
		opts = {
			-- This list tells mason to automatically install these servers.
			-- We will configure them in Section 4.
			ensure_installed = {
				"pyright",
				"clangd",
				"jdtls",
			},
			-- Automatically set up LSPs that are installed
			automatic_installation = true,
		},
	},
		{
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		lazy = false, -- Install tools immediately on startup
		dependencies = { "williamboman/mason.nvim" },
		config = function()
			require("mason-tool-installer").setup({
				ensure_installed = {
					-- Linters/Formatters (Non-LSP tools go here)
					"stylua",       -- Lua formatter
					"black",        -- Python formatter
					"isort",        -- Python import sorter
					"clang-format", -- C/C++ formatter
					"shfmt",        -- Bash formatter
					"bash-language-server",
					"dockerfile-language-server",
				},
				auto_update = true,
				run_on_start = true,
			})
		end,
	},
	{
		'neovim/nvim-lspconfig',
		dependencies = {
			'hrsh7th/cmp-nvim-lsp', -- Bridge between LSP and CMP
			'williamboman/mason.nvim', -- Optional package manager
			'williamboman/mason-lspconfig.nvim',
		},
		config = function()
			-- 1. Setup LspAttach Autocommand (Replaces 'on_attach')
			-- This configuration runs whenever an LSP attaches to a buffer
			vim.api.nvim_create_autocmd('LspAttach', {
				group = vim.api.nvim_create_augroup('UserLspConfig', {}),
				callback = function(ev)
					local opts = { buffer = ev.buf, remap = false }

					-- Buffer Local Keymaps
					vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts) -- Jump to definition
					vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)       -- Hover docs
					vim.keymap.set("n", "<leader>vws", vim.lsp.buf.workspace_symbol, opts)
					vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, opts)
					vim.keymap.set("n", "[d", vim.diagnostic.goto_next, opts)
					vim.keymap.set("n", "]d", vim.diagnostic.goto_prev, opts)
					vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
					vim.keymap.set("n", "<leader>rr", vim.lsp.buf.references, opts)
					vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
				end,
			})

			-- 2. Capabilities (for nvim-cmp)
			local capabilities = require('cmp_nvim_lsp').default_capabilities()

			-- 3. Configure Servers using Native API (vim.lsp.config)
			-- C/C++ (clangd)
			vim.lsp.config['clangd'] = {
				capabilities = capabilities,
				cmd = { "clangd", "--background-index" }
			}
			vim.lsp.enable('clangd')

			-- Python (pyright)
			vim.lsp.config['pyright'] = {
				capabilities = capabilities,
			}
			vim.lsp.enable('pyright')

			-- Bash (bashls)
			vim.lsp.config['bashls'] = {
				capabilities = capabilities,
			}
			vim.lsp.enable('bashls')

			-- Dockerfile
			vim.lsp.config['dockerls'] = {
				capabilities = capabilities,
			}
			vim.lsp.enable('dockerls')

			-- Java (jdtls)
			local jdtls_path = "/opt/jdtls"
			local launcher_jar = vim.fn.glob(jdtls_path .. "/plugins/org.eclipse.equinox.launcher_*.jar")
			if launcher_jar ~= "" then
				vim.lsp.config['jdtls'] = {
					capabilities = capabilities,
					cmd = {
						"java",
						"-Declipse.application=org.eclipse.jdt.ls.core.id1",
						"-Dosgi.bundles.defaultStartLevel=4",
						"-Declipse.product=org.eclipse.jdt.ls.core.product",
						"-Dlog.protocol=true",
						"-Dlog.level=ALL",
						"-Xmx1g",
						"--add-modules=ALL-SYSTEM",
						"--add-opens", "java.base/java.util=ALL-UNNAMED",
						"--add-opens", "java.base/java.lang=ALL-UNNAMED",
						"-jar", launcher_jar,
						"-configuration", jdtls_path .. "/config_linux",
						"-data", vim.fn.expand("~/.cache/jdtls-workspace") .. vim.fn.getcwd()
					},
					root_markers = {".git", "mvnw", "gradlew", "pom.xml", "build.gradle"},
				}
				vim.lsp.enable('jdtls')
			end
		end
	},
	{
		"hrsh7th/nvim-cmp",
		event = "InsertEnter",
		dependencies = {
			"hrsh7th/cmp-nvim-lsp",    -- LSP source
			"hrsh7th/cmp-buffer",      -- Buffer source
			"hrsh7th/cmp-path",        -- Path source
			"L3MON4D3/LuaSnip",      -- Snippet engine
			"saadparwaiz1/cmp_luasnip", -- Snippet source
			"onsails/lspkind.nvim",    -- Icons for completion
		},
		config = function()
			local cmp = require("cmp")
			local luasnip = require("luasnip")
			local lspkind = require("lspkind")

			cmp.setup({
				snippet = {
					expand = function(args)
						luasnip.lsp_expand(args.body)
					end,
				},
				sources = cmp.config.sources({
					{ name = "nvim_lsp" },
					{ name = "luasnip" },
					{ name = "buffer" },
					{ name = "path" },
				}),
				mapping = cmp.mapping.preset.insert({
					["<C-k>"] = cmp.mapping.select_prev_item(),
					["<C-j>"] = cmp.mapping.select_next_item(),
					["<C-b>"] = cmp.mapping.scroll_docs(-4),
					["<C-f>"] = cmp.mapping.scroll_docs(4),
					['<C-Space>'] = cmp.mapping.complete(),
					["<C-e>"] = cmp.mapping.abort(),
					['<CR>'] = cmp.mapping.confirm({ select = true }),
					['<Tab>'] = cmp.mapping(function(fallback)
						if cmp.visible() then
							cmp.select_next_item()
						elseif luasnip.expand_or_jumpable() then
							luasnip.expand_or_jump()
						else
							fallback()
						end
					end, { 'i', 's' })
				}),
				formatting = {
					format = lspkind.cmp_format({
						mode = "symbol",
						maxwidth = 50,
					}),
				},
			})
		end,
	},
}
