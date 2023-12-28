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
        keybinds.register_keybinds(module.name, { "next-iteration", "stop-iteration" })
    end)
end

module.on_event = function(event)
    if event.split_type[2] == (module.name .. ".next-iteration") then
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

        local _, column = current:start()

        -- Set cursor_pos to insert the new item at the end of the current node
        cursor_pos = current:end_()

        -- Hack to fix issue where the end of node is one row short for a list
        -- item that is followed by an empty line. Checks if `current` is an
        -- ordered or unordered list item and if the next line is empty; if so,
        -- add 1 to cursor_pos.
        -- Note: cursor_pos + 1 is the next line for the problematic case where
        -- the following line is empty; but cursor_pos should be the next line
        -- in other cases, so this would seem to be checking 2 lines ahead in
        -- that case; still, it seems to be working as is.
        if current:type():match("list%d") then
            local line_after = vim.api.nvim_buf_get_lines(event.buffer, cursor_pos + 1, cursor_pos + 2, true)[1]
            local line_after_is_empty = not line_after:match("%S")
            if line_after_is_empty then
                cursor_pos = cursor_pos + 1
            end
        end

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
        [module.name .. ".next-iteration"] = true,
        [module.name .. ".stop-iteration"] = true,
    },
}

return module
-- vim:tabstop=4:shiftwidth=4:expandtab
