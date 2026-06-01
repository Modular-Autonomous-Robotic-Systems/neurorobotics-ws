-- lua/plugins/core.lua
return {
    {
        "nvim-treesitter/nvim-treesitter",
        branch = "master", -- v1 API; v2 (main) requires GLIBC 2.39 via tree-sitter-cli
        build = ":TSUpdate",
        config = function()
            require("nvim-treesitter.configs").setup({
                branch = "master", -- v1 API; v2 (main) requires GLIBC 2.39 via tree-sitter-cli
                build = ":TSUpdate",
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
            vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>", { desc = "Toggle File Explorer" })
        end,
    },
    {
        "ibhagwan/fzf-lua",
        cmd = "FzfLua",
        keys = {
            { "<leader>ff", "<cmd>FzfLua files<CR>", desc = "Find files" },
            { "<leader>fg", "<cmd>FzfLua live_grep<CR>", desc = "Find in files (Grep)" },
            { "<leader>fs", "<cmd>FzfLua lsp_document_symbols<CR>", desc = "Find symbols" },
        },
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            require("fzf-lua").setup({
                winopts = {
                    border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
                },
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
        end,
    },
}
