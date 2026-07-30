-- lua/plugins/ai.lua
return {
    {
        "carlos-algms/agentic.nvim",
        event = "VeryLazy",
        opts = {
            provider = "claude-agent-acp",

            acp_providers = {
                ["gemini-acp"] = {
                    command = "gemini",
                },
                ["claude-agent-acp"] = {
                    command = "claude-agent-acp",
                },
            },

            windows = {
                position = "right",
                width = "30%",
                height = "25%",
            },

            diff_preview = {
                enabled = true,
                layout = "split",
                center_on_navigate_hunks = true,
            },
        },

        keys = {
            -- Fast toggle from any mode
            {
                "<C-\\>",
                function()
                    require("agentic").toggle()
                end,
                mode = { "n", "v", "i" },
                desc = "AI: Toggle sidebar",
            },

            -- Sidebar management
            {
                "<leader>zt",
                function()
                    require("agentic").toggle()
                end,
                desc = "AI: Toggle sidebar",
            },
            {
                "<leader>zl",
                function()
                    require("agentic").rotate_layout()
                end,
                desc = "AI: Rotate layout (right/bottom/left)",
            },

            -- Session management
            {
                "<leader>zn",
                function()
                    require("agentic").new_session()
                end,
                mode = { "n", "v", "i" },
                desc = "AI: New session",
            },
            {
                "<leader>zr",
                function()
                    require("agentic").restore_session()
                end,
                desc = "AI: Restore previous session",
            },

            -- Context: send selection (visual) or current file (normal)
            {
                "<leader>zs",
                function()
                    require("agentic").add_selection_or_file_to_context()
                end,
                mode = { "n", "v" },
                desc = "AI: Add selection or file to context",
            },
            -- Context: explicitly add current file
            {
                "<leader>zf",
                function()
                    require("agentic").add_file()
                end,
                desc = "AI: Add current file to context",
            },

            -- Diagnostics
            {
                "<leader>zd",
                function()
                    require("agentic").add_current_line_diagnostics()
                end,
                desc = "AI: Add current line diagnostics",
            },
            {
                "<leader>zD",
                function()
                    require("agentic").add_buffer_diagnostics()
                end,
                desc = "AI: Add all buffer diagnostics",
            },

            -- Provider switching (preserves chat history)
            {
                "<leader>zm",
                function()
                    require("agentic").switch_provider()
                end,
                desc = "AI: Switch provider (Gemini/Claude)",
            },

            -- Stop generation
            {
                "<leader>zq",
                function()
                    require("agentic").stop_generation()
                end,
                desc = "AI: Stop generation",
            },
        },
    },
    {
        "MeanderingProgrammer/render-markdown.nvim",
        -- ...
        opts = {
            file_types = { "markdown", "md", "AgenticChat" },
            latex = {
                enabled = true,
                -- Appearance of the render
                converter = "latex2text", -- Requires 'latex2text' installed on your system
                highlight = "RenderMarkdownMath",
                top_pad = 0,
                bottom_pad = 0,
            },
            -- Important for agentic.nvim: ensure the plugin treats AI chat as markdown
            overrides = {
                buftype = {
                    nofile = {
                        -- This helps if agentic.nvim uses 'nofile' buffers
                        enabled = true,
                    },
                },
            },
        },
    },
}
