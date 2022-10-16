local api = vim.api
local strdisplaywidth = vim.fn.strdisplaywidth

------- PURE START --------
local function get_matches(lines, pattern, ignorebadlines)
    local ok, re = pcall(vim.regex, pattern)
    if not ok then return nil, { type="BAD_REGEX", msg=re } end

    -- we need the indices of the matches to know where to split the string
    local match_indices = {}
    -- and the columns to know how many spaces to insert
    -- to support characters that take up multiple columns (eg. tabs)
    local match_columns = {}
    -- and we want the end indices for highlighting
    local end_indices = {}

    for i = 1, #lines do
        match_indices[i], end_indices[i] = re:match_str(lines[i])
        if match_indices[i] then
            match_columns[i] = strdisplaywidth(lines[i]:sub(1, match_indices[i]))

        -- ignore lines that don't match if they're empty or `ignorebadlines` is set
        elseif not ignorebadlines and lines[i] ~= "" then
            return nil, { type="BAD_LINE", line_idx=i }
        end
    end

    return { indices=match_indices, columns=match_columns, ends=end_indices }
end

local function get_target_column(matches)
    local targetcol = 0
    for k,v in pairs(matches.columns) do
        if v and v > targetcol then targetcol = v end
    end
    return targetcol
end

local function get_inserts(lines, matches)
    local targetcol = get_target_column(matches)
    inserts = {}
    for i = 1, #lines do
        local s, index, column = lines[i], matches.indices[i], matches.columns[i]
        if index and column < targetcol then
            inserts[i] = {start=index+1, text=string.rep(' ', targetcol - column)}
        end
    end
    return inserts
end

local function apply_inserts(lines, toinsert)
    local new_lines = {}
    for i = 1, #lines do
        local insert = toinsert[i]
        if insert then
            local left = lines[i]:sub(1, insert.start - 1)
            local right = lines[i]:sub(insert.start)
            new_lines[i] = left..insert.text..right
        else
            new_lines[i] = lines[i]
        end
    end
    return new_lines
end

------- PURE END --------

local function on_align_command(ctx)
    local startline = ctx.line1 - 1 --to 0-based index
    local buffer = 0

    -- lines must exist if it's a valid range, right?
    local lines = assert(api.nvim_buf_get_lines(buffer, startline, ctx.line2, false))

    local matches, err = get_matches(lines, ctx.args, ctx.bang)
    if not matches then
        if err.type == "BAD_REGEX" then
            print(err.msg)
        elseif err.type == "BAD_LINE" then
            print(string.format('Line (number %d) failed to match given regular expression `%s` (use ! to ignore)', err.line_idx+startline, ctx.args))
        end
        return
    end
    local inserts = get_inserts(lines, matches)
    local new_lines = apply_inserts(lines, inserts)
    api.nvim_buf_set_lines(buffer, startline, ctx.line2, false, new_lines)
end

local function align_preview(ctx, preview_ns, preview_buf)
    local startline = ctx.line1 - 1 --to 0-based index
    local buffer = 0

    -- lines must exist if it's a valid range, right?
    local lines = assert(api.nvim_buf_get_lines(buffer, startline, ctx.line2, false))

    local matches, error_index = get_matches(lines, ctx.args, ctx.bang)
    if matches then
        local inserts = get_inserts(lines, matches)
        local new_lines = apply_inserts(lines, inserts)

        -- set lines
        api.nvim_buf_set_lines(buffer, startline, ctx.line2, false, new_lines)

        local targetcol = get_target_column(matches)

        for i = 1, #lines do
            -- highlight inserts
            if inserts[i] then
                api.nvim_buf_add_highlight(
                    buffer,
                    preview_ns,
                    'Substitute',
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
                    is_leading and 'IncSearch' or 'Search',
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
            api.nvim_buf_add_highlight(buffer, preview_ns, 'Substitute', startline + i-1, start_idx-1, end_idx-1)
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
    bang = true, range = 1, nargs = 1, preview = align_preview,
})
api.nvim_create_user_command("Unalign", on_unalign_command, {range = 1, preview = unalign_preview})
