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
    modula:registerForEvents(self, "onStart", "onStopping", "onCheckMachines", "onCommand")
    self.orderName = parameters.orderName or "samedicorp.auto-industry.default-order"
    self.reportMachines = parameters.reportMachines or true
    self.problems = {}
    self.problemsChanged = true
end

-- ---------------------------------------------------------------------
-- Event handlers
-- ---------------------------------------------------------------------

function Module:onStart()
    debugf("Auto Industry started.")

    self:attachToScreen()
    local industry = modula:getService("industry")
    self.industry = industry


    local order = require(self.orderName)
    local buildList = {}

    self:addOrder(buildList, order.refiner, "Basic Refiner")
    self:addOrder(buildList, order.smelter, "Basic Smelter")
    self:addOrder(buildList, order.metalwork, "Basic Metalwork Industry")
    self:addOrder(buildList, order.chemical, "Basic Chemical industry")
    self:addOrder(buildList, order.glass, "Basic Glass Furnace")
    self:addOrder(buildList, order.electronics, "Basic Electronics industry")
    self:addOrder(buildList, order.electronicsU, "Uncommon Electronics industry")
    self:addOrder(buildList, order.printer, "Basic 3D Printer")

    local recipes = {}

    for recipe, order in pairs(buildList) do
        local machineRecipe = recipes[order.machine]
        if not machineRecipe then
            machineRecipe = {}
            recipes[order.machine] = machineRecipe
        end
        table.insert(machineRecipe, recipe)
    end

    self.buildList = buildList
    self.recipes = recipes

    modula:addTimer("onCheckMachines", 2.0)

    self:attachToScreen()

    if self.reportMachines then
        industry:reportMachines()
    end

    local industry = self.industry
    if industry then
        industry:withMachines(function(machine)
            self:updateProblems(machine)
        end)
    end

    self:restartMachines()
end

function Module:onStopping()
    debugf("Auto Industry stopping.")
end

function Module:onContainerChanged(container)
    self.screen:send({ name = container:name(), value = container.percentage })
end

function Module:onScreenReply(reply)
    -- printf("reply: %s", reply)
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
        local recipes = self.recipes[machine:label()]
        if not recipes or #recipes == 0 then
            debugf("No recipes for %s - %s", machine:label(), machine:name())
            return
        end

        local index = (1 + (machine.index or 0) % #recipes)
        machine.index = index
        local recipe = recipes[index]
        local buildOrder = self.buildList[recipe]
        if machine:label():find(buildOrder.machine) then
            if not machine:isStopped() then
                machine:stop()
            end

            if machine:setRecipe(recipe) == 0 then
                machine.target = recipe
                machine.actual = nil
                machine:start(buildOrder.quantity)
            end
        end
    elseif machine:isRunning() then
        if machine.actual ~= machine.target then
            debugf("Running '%s' for %s (%s).", system.getItem(machine.target).locDisplayName, machine:name(),
                machine:label())
            machine.actual = machine.target
        end
    end
    self:updateProblems(machine)
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

function Module:updateProblems(machine)
    local problems = self.problems

    local newStatus
    local newDetail

    local product = machine:mainProduct()
    if not product then
        return
    end

    local order = self.buildList[toString(product.id)] or { quantity = 0 }
    if order.quantity == 0 then
        order.quantity = 1
        debugf("No order for %s (%s)", product.name, machine:name())
    end
    local batchCount = math.ceil(order.quantity / product.mainRecipe.quantity)

    if machine:isMissingIngredients() then
        local ingredients = {}
        if order then
            batchCount = order.quantity / product.mainRecipe.quantity
            debugf("%s x%s (%s batches) missing ingredients", product.name, order.quantity, batchCount)

            for n, input in pairs(product.mainRecipe.ingredients) do
                local iName = system.getItem(input.id).locDisplayName
                table.insert(ingredients, string.format("%s %s", iName, math.floor(input.quantity * batchCount)))
            end
        end
        newStatus = string.format("%s Needs Ingredients", machine:name())
        newDetail = table.concat(ingredients, ", ")
    elseif machine:isMissingSchematics() then
        newStatus = "Needs Schematics"
    elseif machine:isFull() then
        newStatus = "Output Full"
    elseif machine:isRunning() then
        newStatus = "Running"
        if order.quantity > 1 then
            newDetail = string.format("Making %s (%s batches) on %s", math.floor(order.quantity),
                math.floor(batchCount), machine:name())
        else
            newDetail = string.format("Making 1 on %s", machine:name())
        end
    elseif machine:isPending() then
        newStatus = "OK"
        local order = self.buildList[toString(machine:mainProduct().id)]
        if order then
            newDetail = string.format("x %s", math.floor(order.quantity))
        else
            newDetail = string.format("x %s", machine:mainProduct().id)
        end
    end

    if newStatus then
        local product = machine:mainProduct()

        local key = product.name
        if newDetail == nil then
            newDetail = machine:name()
        end
        if problems[key] ~= newStatus then
            problems[key] = newStatus
            local screen = self.screen
            if screen then
                screen:send({ command = "status", status = { key = key, value = newStatus, detail = newDetail } })
            end
        end
    end
end

function Module:addOrder(buildList, itemsToAdd, type)
    for id, quantity in pairs(itemsToAdd) do
        buildList[id] = {
            quantity = quantity,
            machine = type,
        }
    end
end

function Module:attachToScreen()
    local service = modula:getService("screen")
    if service then
        local screen = service:registerScreen(self, "main", self.renderScript)
        if screen then
            self.screen = screen
        end
    end
end

Module.renderScript = [[

status = status or {}
detail = detail or {}

if payload then
    if payload.command == "status" then
        local key = payload.status.key
        status[key] = payload.status.value
        detail[key] = payload.status.detail
    end
    reply = { name = payload.command, result = "ok" }
end

local screen = toolkit.Screen.new()
local layer = screen:addLayer()

local cOK = toolkit.Color.new(0, 1, 0)
local cRunning = toolkit.Color.new(1, 1, 0)
local cWarn = toolkit.Color.new(1, 0, 0)
local cDetail = toolkit.Color.new(0.39, 0.39, 0.39)
local fDetail = toolkit.Font.new("Play", 12)


local gotItems = false
local y = 22
for n, line in pairs(status) do
    local color
    local skip = false
    if string.find(line, "Running") then
        color = cRunning
    elseif string.find(line, "OK") then
        color = cOK
        skip = true
    else
        color = cWarn
    end

    if not skip then
        local label = layer:addLabel({10, y, 300, y}, n, { fill = color })
        local value = layer:addLabel({300, y, 300, y}, line)
        local l2 = layer:addLabel({302, y + 9, 300, y + 9}, detail[n] or "", { font = fDetail, fill = cDetail })
        y = y + 22
        gotItems = true
    end
end

if not gotItems then
    local label = layer:addLabel({0, 0, 300, 40}, "Starting Industry...")
end

layer:render()
screen:scheduleRefresh()
]]

return Module
