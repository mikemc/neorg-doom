--[[
    file: Doom
    title: Neorg helpers inspired by Doom Emacs
    description: Helpers for editing neorg documents inspired by org-mode in
    Doom Emacs.
    ---
Add module docs here!

The starting point for this file is module.lua from the core.itero module
--]]

local neorg = require("neorg.core")
local lib, log, modules, utils = neorg.lib, neorg.log, neorg.modules, neorg.utils

local module = modules.create("external.doom")

module.setup = function()
    return {
        requires = {
            "core.integrations.treesitter",
        },
    }
end

module.config.public = {
    -- A list of lua patterns detailing what treesitter nodes can be "iterated".
    -- Usually doesn't need to be changed, unless you want to disable some
    -- items from being iterable.
    iterables = {
        "unordered_list%d",
        "ordered_list%d",
        "heading%d",
        "quote%d",
    },

    -- Which item types to retain extensions for.
    --
    -- If the item you are currently iterating has an extension (e.g. `( )`, `(x)` etc.),
    -- then the following items will also have an extension (by default `( )`) attached
    -- to them automatically.
    retain_extensions = {
        ["unordered_list%d"] = true,
        ["ordered_list%d"] = true,
    },
}

module.config.private = {
    stop_types = {
        "generic_list",
        "quote",
    },
}

module.load = function()
    modules.await("core.keybinds", function(keybinds)
        keybinds.register_keybinds(module.name, { "insert-item-below" })
    end)
end

module.on_event = function(event)
    if event.split_type[2] == (module.name .. ".insert-item-below") then
        local ts = module.required["core.integrations.treesitter"]
        -- Question: Why do we need to subtract 1 from the cursor position? Perhaps from a change from 1-indexing to 0-indexing?
        local cursor_pos = event.cursor_position[1] - 1

        local current = ts.get_first_node_on_line(event.buffer, cursor_pos, module.config.private.stop_types)

        if not current then
            log.error(
                "Treesitter seems to be high and can't properly grab the node under the cursor. Perhaps try again?"
            )
            return
        end

        -- Find the first parent node that is an iterable
        while current:parent() do
            if
                lib.filter(module.config.public.iterables, function(_, iterable)
                    return current:type():match(table.concat({ "^", iterable, "$" })) and iterable or nil
                end)
            then
                break
            end

            current = current:parent()
        end

        if not current or current:type() == "document" then
            local fallback = event.content[1]

            if fallback then
                assert(
                    type(fallback) == "string",
                    "Invalid argument provided to `next-iterable` keybind! Option should be of type `string`!"
                )

                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(fallback, true, true, true), "t", false)
                return
            end

            utils.notify(
                "No object to continue! Make sure you're under an iterable item like a list or heading.",
                vim.log.levels.WARN
            )
            return
        end

        local should_append_extension = lib.filter(
            module.config.public.retain_extensions,
            function(match, should_append)
                return current:type():match(match) and should_append or nil
            end
        ) and current:named_child(1) and current:named_child(1):type() == "detached_modifier_extension"

        local text_to_repeat = ts.get_node_text(current:named_child(0), event.buffer)

        -- Column to indent to
        local _, column = current:start()

        -- Determine the row to insert the new line after the end of the
        -- current node. There are two cases; for list items that are followed
        -- by a blank line, the end of the node as returned by treesitter will
        -- be on the line with text (in which case, we need to add 1 to then
        -- end row); for other cases, it will be at column 0 of the following
        -- line (in which case we can use the end row).
        local end_row, end_col = current:end_()
        cursor_pos = end_row + (end_col == 0 and 0 or 1)

        vim.api.nvim_buf_set_lines(
            event.buffer,
            cursor_pos,
            cursor_pos,
            true,
            { string.rep(" ", column) .. text_to_repeat .. (should_append_extension and "( ) " or "") }
        )
        vim.api.nvim_win_set_cursor(
            event.window,
            { cursor_pos + 1, column + text_to_repeat:len() + (should_append_extension and ("( ) "):len() or 0) }
        )
    end
end

module.events.subscribed = {
    ["core.keybinds"] = {
        [module.name .. ".insert-item-below"] = true,
    },
}

return module
-- vim:tabstop=4:shiftwidth=4:expandtab
