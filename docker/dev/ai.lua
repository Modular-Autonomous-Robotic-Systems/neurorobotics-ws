-- lua/plugins/ai.lua
return {
    {
        "carlos-algms/agentic.nvim",
        event = "VeryLazy",
        opts = {
            -- Default provider: gemini (current behaviour preserved)
            provider = "gemini-acp",

            acp_providers = {
                ["gemini-acp"] = {
                    command = "gemini",
                },
                ["claude-acp"] = {
                    command = "claude-acp",
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
                "<leader>at",
                function()
                    require("agentic").toggle()
                end,
                desc = "AI: Toggle sidebar",
            },
            {
                "<leader>al",
                function()
                    require("agentic").rotate_layout()
                end,
                desc = "AI: Rotate layout (right/bottom/left)",
            },

            -- Session management
            {
                "<leader>an",
                function()
                    require("agentic").new_session()
                end,
                mode = { "n", "v", "i" },
                desc = "AI: New session",
            },
            {
                "<leader>ar",
                function()
                    require("agentic").restore_session()
                end,
                desc = "AI: Restore previous session",
            },

            -- Context: send selection (visual) or current file (normal)
            {
                "<leader>as",
                function()
                    require("agentic").add_selection_or_file_to_context()
                end,
                mode = { "n", "v" },
                desc = "AI: Add selection or file to context",
            },
            -- Context: explicitly add current file
            {
                "<leader>af",
                function()
                    require("agentic").add_file()
                end,
                desc = "AI: Add current file to context",
            },

            -- Diagnostics
            {
                "<leader>ad",
                function()
                    require("agentic").add_current_line_diagnostics()
                end,
                desc = "AI: Add current line diagnostics",
            },
            {
                "<leader>aD",
                function()
                    require("agentic").add_buffer_diagnostics()
                end,
                desc = "AI: Add all buffer diagnostics",
            },

            -- Provider switching (preserves chat history)
            {
                "<leader>am",
                function()
                    require("agentic").switch_provider()
                end,
                desc = "AI: Switch provider (Gemini/Claude)",
            },

            -- Stop generation
            {
                "<leader>aq",
                function()
                    require("agentic").stop_generation()
                end,
                desc = "AI: Stop generation",
            },
        },
    },
}
