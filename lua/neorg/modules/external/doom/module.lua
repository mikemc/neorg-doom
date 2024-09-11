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
      "core.promo",
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
  ---@type core.esupports.indent                         -- from promo
  indent = module.required["core.esupports.indent"]      -- from promo

  vim.keymap.set("n", "<Plug>(neorg.doom.insert-item-below)",
    function() module.private.insert_item("below") end
  )
  vim.keymap.set("n", "<Plug>(neorg.doom.insert-item-above)",
    function() module.private.insert_item("above") end
  )
  vim.keymap.set("n", "<Plug>(neorg.doom.promote)",
    function() module.required["core.promo"].demote() end
  )
  vim.keymap.set("n", "<Plug>(neorg.doom.demote)",
    function() module.required["core.promo"].promote() end
  )
  vim.keymap.set("n", "<Plug>(neorg.doom.promote-subtree)",
    function() module.required["core.promo"].demote_nested() end
  )
  vim.keymap.set("n", "<Plug>(neorg.doom.demote-subtree)",
    function() module.required["core.promo"].promote_nested() end
  )
  vim.keymap.set("n", "<Plug>(neorg.doom.move-subtree-up)",
    function() module.private.move_subtree("up") end
  )
  vim.keymap.set("n", "<Plug>(neorg.doom.move-subtree-down)",
    function() module.private.move_subtree("down") end
  )
  vim.keymap.set("n", "<Plug>(neorg.doom.toggle-heading)", 
    module.private.toggle_heading
  )
  vim.keymap.set("n", "<Plug>(neorg.doom.back-to-heading)", 
    module.private.back_to_heading
  )
end

module.private = {
  -- Insert a new iterable item above or below the current one
  insert_item = function (direction)
    local ts = module.required["core.integrations.treesitter"]

    -- Note: ts.get_first_node_on_line() requires a 0-indexed row;
    -- vim.api.nvim_win_get_cursor(0)[1] is a 1-indexed row returned by
    -- nvim_win_get_cursor()
    local current = ts.get_first_node_on_line(vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)[1] - 1, module.config.private.stop_types)

    if not current then
      log.error(
        "Treesitter can't properly grab the node under the cursor."
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

    -- Taken from the itero module; not sure what this does
    if not current or current:type() == "document" then
      vim.api.nvim_feedkeys(vim.keycode("<CR>"), "n", false)
      return
    end

    local should_append_extension = lib.filter(
      module.config.public.retain_extensions,
      function(match, should_append)
        return current:type():match(match) and should_append or nil
      end
    ) and current:named_child(1) and current:named_child(1):type() == "detached_modifier_extension"

    local text_to_repeat = ts.get_node_text(current:named_child(0), vim.api.nvim_get_current_buf())

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
      vim.api.nvim_get_current_buf(),
      insert_row,
      insert_row,
      true,
      { string.rep(" ", start_col) .. text_to_repeat .. (should_append_extension and "( ) " or "") }
    )
    vim.api.nvim_win_set_cursor(
      vim.api.nvim_get_current_win(),
      { insert_row + 1, start_col + text_to_repeat:len() + (should_append_extension and ("( ) "):len() or 0) }
    )
  end,

  -- Get the first node on the current line
  get_first_node_on_event_line = function ()
    -- Question: Can I use built-in treesitter functions to do this?
    return module.required["core.integrations.treesitter"].get_first_node_on_line(
      vim.api.nvim_get_current_buf(),
      vim.api.nvim_win_get_cursor(0)[1] - 1, 
      module.config.private.stop_types
    )
  end,

  -- Find the parent heading of the current line
  -- If no parent heading, return the document node
  get_heading = function ()
    local current = module.private.get_first_node_on_event_line()
    while current:parent() do
      if current:type():match("^heading%d$") then
        break
      end
      current = current:parent()
    end
    return current
  end,

  -- Move the cursor to the heading of the current subtree
  -- Question: Which column should the cursor be moved to?
  back_to_heading = function ()
    local current = module.private.get_heading()
    local start_row, start_col = current:start()
    vim.api.nvim_win_set_cursor(vim.api.nvim_get_current_win(), {start_row + 1, start_col})
  end,

  -- Move the current subtree up or down
  move_subtree = function (direction)
    -- Find the nearest heading containing the current line; set to 'current' node.
    local current = module.private.get_first_node_on_event_line()
    while current:parent() do
      if current:type():match("^heading%d$") then
        break
      end
      current = current:parent()
    end
    local start_row = current:start()
    local end_row = current:end_()
    -- Then find the sister node above or below (depending on 'direction' argument), if it exists.
    local sibling = nil
    local insert_row = nil
    if (direction == "up") then
      sibling = current:prev_sibling()
      if sibling then 
        insert_row = sibling:start()
      end
    elseif (direction == "down") then
      sibling = current:next_sibling()
      if sibling then 
        insert_row = sibling:end_() - (end_row - start_row)
      end
    else
      log.error('`direction` must be "up" or "down".')
    end
    -- If sibling is not nil, then move the current subtree to other side of sibling and restore cursor position to location in current.
    if sibling then
      local current_text = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), start_row, end_row, true)
      vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), start_row, end_row, true, {})
      vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), insert_row, insert_row, true, current_text)
      vim.api.nvim_win_set_cursor(vim.api.nvim_get_current_win(), {insert_row + 1, vim.api.nvim_win_get_cursor(0)[2]})
    end
  end,

  -- Convert a normal line or list item to a heading, or a heading to a normal line
  -- Note: Does not reindent other content; ideally, when converting a heading I would reindent its child text if necessary.
  toggle_heading = function ()
    local current = module.private.get_first_node_on_event_line()
    local current_text = vim.api.nvim_get_current_line()
    -- If current line is a heading, replace the heading prefix with spaces
    -- Current version uses the indentation level corresponding to the heading's level (not the previous heading, which will become the new parent.)
    if current:type():match("^heading%d$") then
      local prefix = current_text:match("^%s*(%*+)")
      local new_text = current_text:gsub("^%s*%*+", string.rep(" ", #prefix))
      vim.api.nvim_set_current_line(new_text)
    -- Otherwise, convert to a heading
    else
      -- If current node is a list item, first drop the list prefix
      if current:type():match("_list%d$") then
        current_text = current_text:gsub("^%s*[%-~]+", "")
      end
      -- Prepend the prefix of the parent heading to the current line, removing extra spaces.
      -- If no parent heading, use a single asterisk.
      local current_heading = module.private.get_heading()
      local row = current_heading:start()
      local prefix = nil
      if current_heading:type():match("^heading%d$") then
        local heading_text = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), row, row + 1, true)[1]
        prefix = heading_text:match("^%s*%*+")
      else
        prefix = "*"
      end
      vim.api.nvim_set_current_line(
        (current_text:gsub("^%s*", prefix .. " "))
      )
    end
  end,

  -- Convert a normal line or heading to an unordered list item, or a list item to a normal line
  -- STUB
  -- Note: Does not reindent other content; ideally, when converting a heading I would reindent its child text if necessary.
  toggle_item = function ()
    local current = module.private.get_first_node_on_event_line()
    local current_text = vim.api.nvim_get_current_line()
    -- If current line is a list item, replace the list prefix with spaces
    -- TODO: Get the indentation level from the parent heading
    -- need to match different patterns for ordered and unordered lists
    if current:type():match("_list%d$") then
      -- do stuff
      print()
    -- Otherwise, convert to a list item
    else
      -- do stuff
      print()
    end
  end,
}

return module
-- vim:tabstop=2:shiftwidth=2:expandtab
