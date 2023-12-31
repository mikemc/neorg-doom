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
        keybinds.register_keybinds(module.name, { "insert-item-above" })
    end)
end

module.private = {
    -- Insert a new iterable item above or below the current one
    insert_item = function (event, direction)
        local ts = module.required["core.integrations.treesitter"]

        -- Note: ts.get_first_node_on_line() requires a 0-indexed row;
        -- event.cursor_position[1] is a 1-indexed row returned by
        -- nvim_win_get_cursor()
        local current = ts.get_first_node_on_line(event.buffer, event.cursor_position[1] - 1, module.config.private.stop_types)

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
                    "Invalid argument provided to `insert-item` keybind! Option should be of type `string`!"
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

        -- The start column determines the column to indent to; the start row
        -- is also used to determine the insertion row for the "above" method
        local start_row, start_col = current:start()

        -- Determine the row to insert the new item
        local insert_row = nil
        if direction == "above" then
            insert_row = start_row
        elseif direction == "below" then
            -- To determine the row after the end of the current node, there
            -- are two cases. If the current item is followed by a blank line,
            -- the end of the node as returned by treesitter will be at the end
            -- of the last line with text; in this case, we need to add 1 to
            -- the end row. For other cases, the end of the node will be at
            -- column 0 of the following line, so we can just use the end row.
            local end_row, end_col = current:end_()
            insert_row = end_row + (end_col == 0 and 0 or 1)
        end

        -- Insert the new item and move the cursor to the correct location
        vim.api.nvim_buf_set_lines(
            event.buffer,
            insert_row,
            insert_row,
            true,
            { string.rep(" ", start_col) .. text_to_repeat .. (should_append_extension and "( ) " or "") }
        )
        vim.api.nvim_win_set_cursor(
            event.window,
            { insert_row + 1, start_col + text_to_repeat:len() + (should_append_extension and ("( ) "):len() or 0) }
        )
    end
}

module.on_event = function(event)
    if event.split_type[2] == (module.name .. ".insert-item-below") then
        module.private.insert_item(event, "below")
    elseif event.split_type[2] == (module.name .. ".insert-item-above") then
        module.private.insert_item(event, "above")
    end
end

module.events.subscribed = {
    ["core.keybinds"] = {
        [module.name .. ".insert-item-below"] = true,
        [module.name .. ".insert-item-above"] = true,
    },
}

return module
-- vim:tabstop=4:shiftwidth=4:expandtab
