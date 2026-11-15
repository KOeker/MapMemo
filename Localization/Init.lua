local _, A = ...
function A.Locale(locale)
    local selected = A.locales[locale]
    return setmetatable({}, {
        __index = function(_, key)
            return (selected and selected[key]) or A.locales.enUS[key] or key
        end,
    })
end

A.L = A.Locale(type(GetLocale) == "function" and GetLocale() or "enUS")
