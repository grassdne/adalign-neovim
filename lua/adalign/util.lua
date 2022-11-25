-- Pure functions

local strdisplaywidth = vim.fn.strdisplaywidth
local M = {}

function M.get_matches(lines, pattern, ignorebadlines)
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

function M.get_target_column(matches)
    local targetcol = 0
    for k,v in pairs(matches.columns) do
        if v and v > targetcol then targetcol = v end
    end
    return targetcol
end

function M.get_inserts (lines, matches)
    local targetcol = M.get_target_column(matches)
    inserts = {}
    for i = 1, #lines do
        local s, index, column = lines[i], matches.indices[i], matches.columns[i]
        if index and column < targetcol then
            inserts[i] = {start=index+1, text=string.rep(' ', targetcol - column)}
        end
    end
    return inserts
end

function M.apply_inserts(lines, toinsert)
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

return M
