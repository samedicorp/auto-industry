-- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
--  Created by Samedi on 27/08/2022.
--  All code (c) 2022, The Samedi Corporation.
-- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

local useLocal = true        --export: Use require() to load local scripts if present. Useful during development.
local logging = true         --export: Enable controller debug output.
local reportMachines = true  --export: Report connected industry machines on startup.
local reportOrders = true    --export: Report orders read from order file on startup.
local reportProducers = true --export: Report producers registered for each item in the order.

modulaSettings = {
    name = "Auto Industry",
    version = "1.0",
    logging = logging,
    useLocal = useLocal,
    modules = {
        ["samedicorp.modula.modules.industry"] = {},
        ["samedicorp.modula.modules.screen"] = {},
        ["samedicorp.auto-industry.main"] = {
            reportMachines = reportMachines,
            reportOrders = reportOrders,
            reportProducers = reportProducers,
        }
    },
    screens = {
        ["samedicorp.auto-industry.screens.main"] = { name = "main" },
    },
    templates = "samedicorp/auto-industry/templates"
}
