-- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
--  Created by Samedi on 27/08/2022.
--  All code (c) 2022, The Samedi Corporation.
-- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

-- If setting up manually, add the following handler to any connected screens:
-- local failure = modula:call("onScreenReply", output)
-- if failure then
--     error(failure)
-- end

local Module = {}

function Module:register(parameters)
    modula:registerForEvents(self, "onStart", "onStop", "onCheckMachines", "onCommand")
end

-- ---------------------------------------------------------------------
-- Event handlers
-- ---------------------------------------------------------------------

function Module:onStart()
    debugf("Auto Industry started.")

    self:attachToScreen()
    local industry = modula:getService("industry")
    self.industry = industry

    -- Dual Universe item IDs
    -- see http://du-lua.dev/#/items for reference

    local smelter = {
        ["511774178"] = 100,  -- Steel
        ["018262914"] = 100,  -- Al-Fe
        ["2565702107"] = 100, -- Silumin
    }

    local metalwork = {
        ["1799107246"] = 100, -- Basic Pipe
        ["3936127019"] = 100, -- Basic Screw
        ["2662317132"] = 10,  -- Basic Combustion Chamber
        ["994058182"] = 10,   -- Basic Reinforced Frame S
        ["1331181119"] = 10,  -- Basic Hydraulics
    }

    local printer = {
        ["1971447072"] = 10, -- Basic Injector
    }

    local chemical = {
        ["2014531313"] = 100, -- Polycarbonate
    }

    local orders = {}
    self:addOrders(orders, smelter, "Smelter")
    self:addOrders(orders, metalwork, "Metalwork")
    self:addOrders(orders, printer, "Printer")
    self:addOrders(orders, chemical, "Chemical")

    local recipes = {}
    for id, _ in pairs(orders) do
        table.insert(recipes, id)
    end

    self.orders = orders
    self.recipes = recipes

    modula:addTimer("onCheckMachines", 1.0)

    self:attachToScreen()
    industry:reportMachines()
    self:restartMachines()
end

function Module:onStop()
    debugf("Auto Industry stopped.")
end

function Module:onContainerChanged(container)
    self.screen:send({ name = container:name(), value = container.percentage })
end

function Module:onScreenReply(reply)
end

function Module:onCheckMachines()
    self:restartMachines()
end

function Module:restartMachines()
    local industry = self.industry
    if industry then
        industry:withMachines(function(machine)
            self:restartMachine(machine)
        end)
    end
end

function Module:restartMachine(machine)
    if machine:isStopped() or machine:isMissingIngredients() or machine:isMissingSchematics() or machine:isPending() then
        local index = (1 + (machine.index or 0) % #self.recipes)
        machine.index = index
        local recipe = self.recipes[index]
        local order = self.orders[recipe]
        if machine:label():find(order.machine) then
            if not machine:isStopped() then
                machine:stop()
            end

            if machine:setRecipe(recipe) == 0 then
                machine:start(order.quantity)
                debugf("Trying '%s' for %s (%s).", system.getItem(recipe).locDisplayName, machine:name(), machine:label())
            end
        end
    end
end

function Module:onCommand(command, parameters)
    if command == "list" then
        local industry = modula:getService("industry")
        if industry then
            industry:reportMachines()
        else
            debugf("No industry service found.")
        end
    end
end

-- ---------------------------------------------------------------------
-- Internal
-- ---------------------------------------------------------------------


function Module:addOrders(orders, itemsToAdd, type)
    for id, quantity in pairs(itemsToAdd) do
        orders[id] = {
            quantity = quantity,
            machine = type,
        }
    end
end

function Module:attachToScreen()
    local service = modula:getService("screen")
    if service then
        local screen = service:registerScreen(self, false, self.renderScript)
        if screen then
            self.screen = screen
        end
    end
end

Module.renderScript = [[

containers = containers or {}

if payload then
    local name = payload.name
    if name then
        containers[name] = payload
    end
    reply = { name = name, result = "ok" }
end

local screen = toolkit.Screen.new()
local layer = screen:addLayer()
local chart = layer:addChart(layer.rect:inset(10), containers, "Play")

layer:render()
screen:scheduleRefresh()
]]

return Module
