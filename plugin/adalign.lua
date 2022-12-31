local api = vim.api

if vim.g.loaded_adalign ~= nil then return end
vim.g.loaded_adalign = 1

api.nvim_set_hl(0, "AdalignInsertSpace",  { link = "Substitute", default = true })
api.nvim_set_hl(0, "AdalignMatch",        { link = "Search",     default = true })
api.nvim_set_hl(0, "AdalignLeadingMatch", { link = "IncSearch",  default = true })
api.nvim_set_hl(0, "AdalignDeleteSpace",  { link = "Substitute", default = true })

local adalign = require "adalign.util"

local function on_align_command(ctx)
    local startline = ctx.line1 - 1 --to 0-based index
    local buffer = 0

    -- lines must exist if it's a valid range, right?
    local lines = assert(api.nvim_buf_get_lines(buffer, startline, ctx.line2, false))


    local matches, err = adalign.get_matches(lines, ctx.args)
    if not matches then
        return api.nvim_err_writeln(err)
    end
    local inserts = adalign.get_inserts(lines, matches)
    local new_lines = adalign.apply_inserts(lines, inserts)
    api.nvim_buf_set_lines(buffer, startline, ctx.line2, false, new_lines)
end

local function align_preview(ctx, preview_ns, preview_buf)
    local startline = ctx.line1 - 1 --to 0-based index
    local buffer = 0

    -- lines must exist if it's a valid range, right?
    local lines = assert(api.nvim_buf_get_lines(buffer, startline, ctx.line2, false))

    local matches, err = adalign.get_matches(lines, ctx.args)
    if matches then
        local inserts = adalign.get_inserts(lines, matches)
        local new_lines = adalign.apply_inserts(lines, inserts)

        -- set lines
        api.nvim_buf_set_lines(buffer, startline, ctx.line2, false, new_lines)

        local targetcol = adalign.get_target_column(matches)

        for i = 1, #lines do
            -- highlight inserts
            if inserts[i] then
                api.nvim_buf_add_highlight(
                    buffer,
                    preview_ns,
                    'AdalignInsertSpace',
                    startline + i-1,
                    inserts[i].start-1,
                    inserts[i].start-1 + #inserts[i].text
                )
            end

            -- highlight matches
            local is_leading = matches.columns[i] == targetcol
            if matches.indices[i] then
                local chars_inserted = inserts[i] and #inserts[i].text or 0
                api.nvim_buf_add_highlight(
                    buffer,
                    preview_ns,
                    is_leading and 'AdalignLeadingMatch' or 'AdalignMatch',
                    startline + i-1,
                    -- matches indices don't take into account new inserts
                    matches.indices[i] + chars_inserted,
                    matches.ends[i] + chars_inserted
                )
            end
        end
    end
    return 1
end

local function unalign(lines)
    local modified = false
    for i,s in ipairs(lines) do
        lines[i] = s:gsub("(%S) +", "%1 ")
        modified = modified or lines[i] ~= s
    end
    return modified
end

local function unalign_preview(ctx, preview_ns, preview_buf)
    local startline = ctx.line1 - 1 --to 0-based index
    local buffer = 0
    local lines = assert(api.nvim_buf_get_lines(buffer, startline, ctx.line2, false))

    for i, l in ipairs(lines) do
        for start_idx, end_idx in l:gmatch("%S()  +()") do
            api.nvim_buf_add_highlight(buffer, preview_ns, 'AdalignDeleteSpace', startline + i-1, start_idx-1, end_idx-1)
        end
    end
    return 1
end

local function on_unalign_command(ctx)
    local startline = ctx.line1 - 1 --to 0-based index
    local buffer = 0
    local lines = assert(api.nvim_buf_get_lines(buffer, startline, ctx.line2, false))
    if unalign(lines) then api.nvim_buf_set_lines(buffer, startline, ctx.line2, false, lines) end
end

api.nvim_create_user_command("Align", on_align_command, {
    range = 1, nargs = 1, preview = align_preview,
})
api.nvim_create_user_command("Unalign", on_unalign_command, {range = 1, preview = unalign_preview})
