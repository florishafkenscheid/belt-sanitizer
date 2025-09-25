data:extend({
    {
        type = "bool-setting",
        name = "belt-sanitizer-report-pollution",
        setting_type = "startup",
        default_value = true,
        order = "a-a"
    },
    {
        type = "bool-setting",
        name = "belt-sanitizer-report-biters",
        setting_type = "startup",
        default_value = true,
        order = "a-b"
    },
    {
        type = "bool-setting",
        name = "belt-sanitizer-peaceful-mode",
        setting_type = "startup",
        default_value = false,
        order = "a-c"
    },
    {
        type = "bool-setting",
        name = "belt-sanitizer-report-expansion",
        setting_type = "startup",
        default_value = true,
        order = "a-d"
    },
    {
        type = "bool-setting",
        name = "belt-sanitizer-write-diagnostics",
        setting_type = "startup",
        default_value = true,
        order = "a-e"
    },
    {
        type = "int-setting",
        name = "belt-sanitizer-production-check-tick",
        setting_type = "startup",
        default_value = 3600,
        order = "a-f"
    },
    {
        type = "string-setting",
        name = "belt-sanitizer-production-items",
        setting_type = "startup",
        default_value = "automation-science-pack,logistic-science-pack",
        auto_trim = true,
        order = "a-y"
    },
    {
        type = "string-setting",
        name = "belt-sanitizer-production-fluids",
        setting_type = "startup",
        default_value = "water,crude-oil",
        auto_trim = true,
        order = "a-z"
    },
})
