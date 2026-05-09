BillingBanking = {}

local function withSharedAccount(jobName, cb)
    local done = false
    local okResult = false

    TriggerEvent('esx_addonaccount:getSharedAccount', 'society_' .. jobName, function(account)
        if account then
            okResult = cb(account) == true
        end
        done = true
    end)

    while not done do
        Wait(0)
    end

    return okResult
end

function BillingBanking.GetJobMoney(jobName)
    if not jobName then return 0 end

    local banking = Config.Banking or 'renewed'
    if banking == 'esx_addonaccount' and GetResourceState('esx_addonaccount') == 'started' then
        local balance = 0
        withSharedAccount(jobName, function(account)
            balance = account.money or 0
            return true
        end)
        return balance
    end

    if banking == 'renewed' and GetResourceState('Renewed-Banking') == 'started' then
        local ok, money = pcall(function()
            return exports['Renewed-Banking']:getAccountMoney(jobName)
        end)
        return (ok and money) and money or 0
    elseif banking == 'qb' and GetResourceState('qb-banking') == 'started' then
        local ok, balance = pcall(function()
            return exports['qb-banking']:GetAccountBalance(jobName)
        end)
        return (ok and balance) and balance or 0
    elseif banking == 'okok' and GetResourceState('okokBanking') == 'started' then
        local ok, result = pcall(function()
            return exports['okokBanking']:GetAccount(jobName)
        end)
        if ok and result then
            return type(result) == 'number' and result or (result.balance or result.account_balance or 0)
        end
    elseif banking == 'fd' and GetResourceState('fd_banking') == 'started' then
        local ok, result = pcall(function()
            return exports['fd_banking']:GetAccount(jobName)
        end)
        if ok and result then
            return type(result) == 'number' and result or (result.balance or result.account_balance or 0)
        end
    elseif banking == 'tgiann' and GetResourceState('tgiann-bank') == 'started' then
        local ok, balance = pcall(function()
            return exports['tgiann-bank']:GetJobAccountBalance(jobName)
        end)
        return (ok and balance) and balance or 0
    end

    return 0
end

function BillingBanking.AddJobMoney(jobName, amount)
    if not jobName then return false end
    local banking = Config.Banking or 'renewed'

    if banking == 'esx_addonaccount' and GetResourceState('esx_addonaccount') == 'started' then
        return withSharedAccount(jobName, function(account)
            account.addMoney(amount)
            account.save()
            return true
        end)
    end

    if banking == 'renewed' and GetResourceState('Renewed-Banking') == 'started' then
        return pcall(function()
            exports['Renewed-Banking']:addAccountMoney(jobName, amount)
        end)
    elseif banking == 'qb' and GetResourceState('qb-banking') == 'started' then
        local ok, result = pcall(function()
            return exports['qb-banking']:AddMoney(jobName, amount, 'bs_billing')
        end)
        return ok and result == true
    elseif banking == 'okok' and GetResourceState('okokBanking') == 'started' then
        return pcall(function()
            exports['okokBanking']:AddMoney(jobName, amount)
        end)
    elseif banking == 'fd' and GetResourceState('fd_banking') == 'started' then
        return pcall(function()
            exports['fd_banking']:AddMoney(jobName, amount)
        end)
    elseif banking == 'tgiann' and GetResourceState('tgiann-bank') == 'started' then
        return pcall(function()
            exports['tgiann-bank']:AddJobMoney(jobName, amount)
        end)
    end

    return false
end

function BillingBanking.RemoveJobMoney(jobName, amount)
    if not jobName then return false end
    local banking = Config.Banking or 'renewed'

    if banking == 'esx_addonaccount' and GetResourceState('esx_addonaccount') == 'started' then
        return withSharedAccount(jobName, function(account)
            account.removeMoney(amount)
            account.save()
            return true
        end)
    end

    if banking == 'renewed' and GetResourceState('Renewed-Banking') == 'started' then
        return pcall(function()
            exports['Renewed-Banking']:removeAccountMoney(jobName, amount)
        end)
    elseif banking == 'qb' and GetResourceState('qb-banking') == 'started' then
        local ok, result = pcall(function()
            return exports['qb-banking']:RemoveMoney(jobName, amount, 'bs_billing')
        end)
        return ok and result == true
    elseif banking == 'okok' and GetResourceState('okokBanking') == 'started' then
        return pcall(function()
            exports['okokBanking']:RemoveMoney(jobName, amount)
        end)
    elseif banking == 'fd' and GetResourceState('fd_banking') == 'started' then
        return pcall(function()
            exports['fd_banking']:RemoveMoney(jobName, amount)
        end)
    elseif banking == 'tgiann' and GetResourceState('tgiann-bank') == 'started' then
        return pcall(function()
            exports['tgiann-bank']:RemoveJobMoney(jobName, amount)
        end)
    end

    return false
end
