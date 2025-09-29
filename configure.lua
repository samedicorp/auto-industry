-- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
--  Created by Samedi on 27/08/2022.
--  All code (c) 2022, The Samedi Corporation.
-- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

local useLocal = true --export: Use require() to load local scripts if present. Useful during development.
local logging = true  --export: Enable controller debug output.

modulaSettings = {
    name = "Auto Industry",
    version = "1.0",
    logging = logging,
    useLocal = useLocal,
    modules = {
        ["samedicorp.modula.modules.industry"] = {},
        ["samedicorp.modula.modules.screen"] = {},
        ["samedicorp.auto-industry.main"] = {}
    },
    screens = {
        ["samedicorp.auto-industry.screens.main"] = { name = "main" },
    },
    templates = "samedicorp/auto-industry/templates"
}
