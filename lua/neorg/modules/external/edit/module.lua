--[[
    file: Edit
    title: Helpers for editing neorg documents
    description: Expands the power of itero and other core modules.
    ---
Add module docs here!

The starting point for this file is module.lua from the core.itero module
--]]

local neorg = require("neorg.core")
local lib, log, modules, utils = neorg.lib, neorg.log, neorg.modules, neorg.utils

local module = modules.create("external.edit")

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
        local cursor_pos = event.cursor_position[1] - 1

        local current = ts.get_first_node_on_line(event.buffer, cursor_pos, module.config.private.stop_types)

        if not current then
            log.error(
                "Treesitter seems to be high and can't properly grab the node under the cursor. Perhaps try again?"
            )
            return
        end

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

        local is_on_nonempty_line =
            vim.api.nvim_buf_get_lines(event.buffer, cursor_pos, cursor_pos + 1, true)[1]:match("%S")
        if is_on_nonempty_line then
            cursor_pos = cursor_pos + 1
        end

        vim.api.nvim_buf_set_lines(
            event.buffer,
            cursor_pos,
            cursor_pos + (is_on_nonempty_line and 0 or 1),
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
