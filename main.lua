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
    self.reportOrders = parameters.reportOrders or true
    self.reportProducers = parameters.reportProducers or false
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


    local order = require(self.orderName) -- TODO: read from databank instead
    local buildList = {}
    for _, items in pairs(order) do
        self:addOrder(buildList, items)
    end
    self.buildList = buildList

    modula:addTimer("onCheckMachines", 2.0)

    self:attachToScreen()

    if self.reportrders then
        self:reportOrders()
    end

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

function Module:reportOrders()
    local industry = self.industry
    if industry then
        local buildList = self.buildList
        industry:withMachines(function(machine)
            local machineClass = machine:itemId()
            local machineItems = buildList[machineClass]
            if machineItems then
                debugf("machine %s %s has orders:", machine:label(), machineClass)
                for _, item in ipairs(machineItems) do
                    local itemInfo = system.getItem(item.id)
                    debugf("  - %s x%s", itemInfo.locDisplayName, item.quantity)
                end
            end
        end)
    end
end

function Module:restartMachines()
    local industry = self.industry
    if industry then
        industry:withMachines(function(machine)
            self:restartMachine(machine)
        end)
    end
end

function Module:nextRecipeForMachine(machine)
    local recipes = self:recipesForMachine(machine)
    local recipeCount = #recipes
    if recipeCount == 0 then
        return nil
    end

    local index = (1 + (machine.index or 0) % recipeCount)
    machine.index = index
    return recipes[index]
end

function Module:startMachineWith(machine, recipe)
    if machine:setRecipe(recipe.id) == 0 then
        machine.target = recipe.id
        machine.actual = nil
        machine:start(recipe.quantity)
    end
end

function Module:validateRunningMachine(machine)
    if machine.actual ~= machine.target then
        debugf("Running '%s' for %s (%s).", system.getItem(machine.target).locDisplayName, machine:name(),
            machine:label())
        machine.actual = machine.target
    end
end

function Module:restartMachine(machine)
    if machine:isStopped() or machine:isMissingIngredients() or machine:isMissingSchematics() or machine:isPending() then
        local recipe = self:nextRecipeForMachine(machine)
        if not recipe then
            debugf("No recipes for %s - %s", machine:label(), machine:name())
            return
        end

        if not machine:isStopped() then
            machine:stop()
        end

        self:startMachineWith(machine, recipe)
    elseif machine:isRunning() then
        self:validateRunningMachine(machine)
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

function Module:recipesForMachine(machine)
    local machineClass = machine:itemId()
    return self.buildList[machineClass] or {}
end

function Module:orderForProductOnMachine(machine, product)
    local recipes = self:recipesForMachine(machine)
    for i, r in ipairs(recipes or {}) do
        if r.id == product.id then
            return r
        end
    end

    debugf("No order for %s on %s - %s %s", product.name, machine:label(), machine:name(), machine:itemId())
    debugf("Recipes %s", toString(recipes))
    return nil
end

function Module:updateProblems(machine)
    local problems = self.problems

    local newStatus
    local newDetail

    local product = machine:mainProduct()
    if not product then
        return
    end

    local order = self:orderForProductOnMachine(machine, product)

    local mainRecipe = product:mainRecipe()
    local mainQuantity = mainRecipe.mainProduct.quantity
    local batchCount
    if not order then
        batchCount = 1
        debugf("No order for %s (%s)", product.name, machine:name())
    else
        batchCount = math.ceil(order.quantity / mainQuantity)
    end
    if machine:isMissingIngredients() then
        local ingredients = {}
        if order then
            if order.quantity > 0 then
                debugf("%s x%s (%s batches) missing ingredients.", product.name, order.quantity, batchCount)
            else
                debugf("%s missing ingredients.", product.name)
            end
            for n, input in pairs(mainRecipe.ingredients) do
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
        if order and order.quantity > 1 then
            newDetail = string.format("Making %s (%s batches) on %s", math.floor(order.quantity),
                math.floor(batchCount), machine:name())
        else
            newDetail = string.format("Making on %s", machine:name())
        end
    elseif machine:isPending() then
        newStatus = "OK"
        if order then
            newDetail = string.format("x %s", math.floor(order.quantity))
        else
            newDetail = string.format("x %s", product.id)
        end
    end

    if newStatus then
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

function Module:addOrder(buildList, itemsToAdd)
    local reportProducers = self.reportProducers
    local industry = self.industry
    for id, quantity in pairs(itemsToAdd) do
        local p = industry:productForItem(id)
        if p then
            for _, r in ipairs(p.recipes) do
                for n, producer in ipairs(r.producers) do
                    if reportProducers then
                        debugf("registered producer %s for %s", system.getItem(producer).locDisplayName, p.name)
                    end
                    local itemList = buildList[producer]
                    if not itemList then
                        itemList = {}
                        buildList[producer] = itemList
                    end
                    table.insert(itemList, { id = id, quantity = quantity })
                end
            end
        end
    end
end

function Module:attachToScreen()
    local service = modula:getService("screen")
    if service then
        local screen = service:registerScreen(self, "main", "samedicorp.auto-industry.screens.main")
        if screen then
            self.screen = screen
        end
    end
end

return Module
