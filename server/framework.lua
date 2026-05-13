BillingFramework = {}

local FRAMEWORK = (Config and Config.Framework) or 'qbx'
if FRAMEWORK ~= 'qb' and FRAMEWORK ~= 'esx' then
    FRAMEWORK = 'qbx'
end

local ESX = nil
if FRAMEWORK == 'esx' and GetResourceState('es_extended') == 'started' then
    local ok = pcall(function()
        ESX = exports['es_extended']:getSharedObject()
    end)
    if not ok or not ESX then
        ESX = nil
    end
end

local function getLicense(source)
    local identifiers = GetPlayerIdentifiers(source) or {}
    for i = 1, #identifiers do
        local value = identifiers[i]
        if value and value:sub(1, 8) == 'license:' then
            return value
        end
    end
    return nil
end

function BillingFramework.GetPlayer(source)
    if not source then return nil end

    if FRAMEWORK == 'qb' then
        if GetResourceState('qb-core') ~= 'started' then return nil end
        local ok, core = pcall(function()
            return exports['qb-core']:GetCoreObject()
        end)
        if not ok or not core or not core.Functions then return nil end
        return core.Functions.GetPlayer(source)
    end

    if FRAMEWORK == 'esx' then
        if not ESX then return nil end
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return nil end

        local job = xPlayer.getJob()
        local first, last = '', ''
        if xPlayer.get then
            first = xPlayer.get('firstName') or xPlayer.get('firstname') or ''
            last = xPlayer.get('lastName') or xPlayer.get('lastname') or ''
        end
        if first == '' and last == '' and xPlayer.getName then
            local full = xPlayer.getName() or ''
            local space = full:find(' ')
            if space then
                first = full:sub(1, space - 1)
                last = full:sub(space + 1)
            else
                first = full
            end
        end

        return {
            PlayerData = {
                source = source,
                citizenid = xPlayer.identifier,
                job = job and {
                    name = job.name,
                    label = job.label,
                    grade = { level = job.grade or 0 },
                } or nil,
                charinfo = { firstname = first, lastname = last },
                license = getLicense(source)
            },
            _xPlayer = xPlayer
        }
    end

    if GetResourceState('qbx_core') ~= 'started' then return nil end
    local ok, player = pcall(function()
        return exports.qbx_core:GetPlayer(source)
    end)
    return ok and player or nil
end

function BillingFramework.GetIdentifier(playerOrSource)
    local player = playerOrSource
    if type(playerOrSource) == 'number' then
        player = BillingFramework.GetPlayer(playerOrSource)
    end
    if not player or not player.PlayerData then return nil end
    return player.PlayerData.citizenid
end

function BillingFramework.GetPlayerName(playerOrSource)
    local player = playerOrSource
    if type(playerOrSource) == 'number' then
        player = BillingFramework.GetPlayer(playerOrSource)
    end
    if not player or not player.PlayerData then return 'Unknown' end

    local ci = player.PlayerData.charinfo or {}
    local full = (ci.firstname or '') .. ' ' .. (ci.lastname or '')
    full = full:gsub('^%s+', ''):gsub('%s+$', '')
    if full ~= '' then return full end

    if player._xPlayer and player._xPlayer.getName then
        return player._xPlayer.getName() or 'Unknown'
    end

    return tostring(player.PlayerData.name or player.PlayerData.citizenid or 'Unknown')
end

function BillingFramework.GetPlayerJob(playerOrSource)
    local player = playerOrSource
    if type(playerOrSource) == 'number' then
        player = BillingFramework.GetPlayer(playerOrSource)
    end
    if not player or not player.PlayerData then return nil end
    return player.PlayerData.job
end

function BillingFramework.GetMoney(playerOrSource, account)
    local player = playerOrSource
    if type(playerOrSource) == 'number' then
        player = BillingFramework.GetPlayer(playerOrSource)
    end
    if not player or not player.PlayerData then return 0 end

    local moneyAccount = account or Config.Account or 'bank'

    if FRAMEWORK == 'qb' then
        if player.Functions and player.Functions.GetMoney then
            return player.Functions.GetMoney(moneyAccount) or 0
        end
        return 0
    end

    if FRAMEWORK == 'esx' then
        local xPlayer = player._xPlayer or (ESX and ESX.GetPlayerFromId(player.PlayerData.source))
        if not xPlayer then return 0 end
        local accountData = xPlayer.getAccount(moneyAccount)
        return accountData and accountData.money or 0
    end

    local cid = player.PlayerData.citizenid
    if not cid then return 0 end
    local ok, amount = pcall(function()
        return exports.qbx_core:GetMoney(cid, moneyAccount)
    end)
    return (ok and amount) and amount or 0
end

function BillingFramework.AddMoney(playerOrSource, account, amount, reason)
    local player = playerOrSource
    if type(playerOrSource) == 'number' then
        player = BillingFramework.GetPlayer(playerOrSource)
    end
    if not player or not player.PlayerData then return false end

    local moneyAccount = account or Config.Account or 'bank'
    local note = reason or 'bs_billing'

    if FRAMEWORK == 'qb' then
        if player.Functions and player.Functions.AddMoney then
            player.Functions.AddMoney(moneyAccount, amount, note)
            return true
        end
        return false
    end

    if FRAMEWORK == 'esx' then
        local xPlayer = player._xPlayer or (ESX and ESX.GetPlayerFromId(player.PlayerData.source))
        if not xPlayer then return false end
        xPlayer.addAccountMoney(moneyAccount, amount, note)
        return true
    end

    local cid = player.PlayerData.citizenid
    if not cid then return false end
    local ok, result = pcall(function()
        return exports.qbx_core:AddMoney(cid, moneyAccount, amount, note)
    end)
    return ok and result == true
end

--- Pay bank (or configured account) by framework identifier (citizenid / QB cid), including offline players when supported.
function BillingFramework.AddMoneyByIdentifier(identifier, account, amount, reason)
    if not identifier or identifier == '' then return false end
    amount = tonumber(amount)
    if not amount or amount <= 0 then return false end

    local moneyAccount = account or Config.Account or 'bank'
    local note = reason or 'bs_billing'

    if FRAMEWORK == 'qb' then
        if GetResourceState('qb-core') ~= 'started' then return false end
        local ok, core = pcall(function()
            return exports['qb-core']:GetCoreObject()
        end)
        if not ok or not core or not core.Functions then return false end

        local online = core.Functions.GetPlayerByCitizenId(identifier)
        if online and online.Functions and online.Functions.AddMoney then
            online.Functions.AddMoney(moneyAccount, amount, note)
            return true
        end

        if core.Functions.GetOfflinePlayerByCitizenId then
            local offline = core.Functions.GetOfflinePlayerByCitizenId(identifier)
            if offline and offline.Functions and offline.Functions.AddMoney then
                offline.Functions.AddMoney(moneyAccount, amount, note)
                if offline.Functions.Save then
                    offline.Functions.Save()
                end
                return true
            end
        end
        return false
    end

    if FRAMEWORK == 'esx' then
        if not ESX then return false end
        local xPlayer = ESX.GetPlayerFromIdentifier and ESX.GetPlayerFromIdentifier(identifier)
        if xPlayer and xPlayer.addAccountMoney then
            xPlayer.addAccountMoney(moneyAccount, amount, note)
            return true
        end
        return false
    end

    if GetResourceState('qbx_core') ~= 'started' then return false end
    local ok, result = pcall(function()
        return exports.qbx_core:AddMoney(identifier, moneyAccount, amount, note)
    end)
    return ok and result == true
end

function BillingFramework.RemoveMoney(playerOrSource, account, amount, reason)
    local player = playerOrSource
    if type(playerOrSource) == 'number' then
        player = BillingFramework.GetPlayer(playerOrSource)
    end
    if not player or not player.PlayerData then return false end

    local moneyAccount = account or Config.Account or 'bank'
    local note = reason or 'bs_billing'

    if FRAMEWORK == 'qb' then
        if player.Functions and player.Functions.RemoveMoney then
            return player.Functions.RemoveMoney(moneyAccount, amount, note)
        end
        return false
    end

    if FRAMEWORK == 'esx' then
        local xPlayer = player._xPlayer or (ESX and ESX.GetPlayerFromId(player.PlayerData.source))
        if not xPlayer then return false end
        xPlayer.removeAccountMoney(moneyAccount, amount, note)
        return true
    end

    local cid = player.PlayerData.citizenid
    if not cid then return false end
    local ok, result = pcall(function()
        return exports.qbx_core:RemoveMoney(cid, moneyAccount, amount, note)
    end)
    return ok and result == true
end

function BillingFramework.GetSourceByIdentifier(identifier)
    if not identifier then return nil end

    if FRAMEWORK == 'esx' then
        if not ESX then return nil end
        if ESX.GetPlayerFromIdentifier then
            local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
            if xPlayer and xPlayer.source then
                return xPlayer.source
            end
        end
        local players = GetPlayers() or {}
        for i = 1, #players do
            local src = tonumber(players[i])
            local xPlayer = ESX.GetPlayerFromId(src)
            if xPlayer and xPlayer.identifier == identifier then
                return src
            end
        end
        return nil
    end

    if FRAMEWORK == 'qb' then
        if GetResourceState('qb-core') ~= 'started' then return nil end
        local ok, core = pcall(function()
            return exports['qb-core']:GetCoreObject()
        end)
        if ok and core and core.Functions and core.Functions.GetPlayerByCitizenId then
            local player = core.Functions.GetPlayerByCitizenId(identifier)
            if player and player.PlayerData then
                return player.PlayerData.source
            end
        end
        return nil
    end

    if GetResourceState('qbx_core') ~= 'started' then return nil end
    local ok, player = pcall(function()
        return exports.qbx_core:GetPlayerByCitizenId(identifier)
    end)
    if ok and player and player.PlayerData then
        return player.PlayerData.source
    end
    return nil
end

function BillingFramework.CanCreateBusinessBill(source, jobName)
    local player = BillingFramework.GetPlayer(source)
    if not player then return false end

    local job = BillingFramework.GetPlayerJob(player)
    if not job or not job.name then return false end

    local targetJob = jobName or job.name
    if job.name ~= targetJob then return false end

    local minGrade = Config.BusinessBillingJobs and Config.BusinessBillingJobs[targetJob]
    if minGrade == nil then return false end

    local grade = job.grade and (job.grade.level or job.grade) or 0
    return grade >= minGrade
end

function BillingFramework.GetJobLabel(jobName)
    if not jobName or jobName == '' then return nil end

    if FRAMEWORK == 'esx' then
        if not ESX then return nil end
        local ok, jobs = pcall(function()
            return ESX.GetJobs and ESX.GetJobs() or {}
        end)
        if ok and jobs and jobs[jobName] then
            return jobs[jobName].label or jobName
        end
        return nil
    end

    if FRAMEWORK == 'qb' then
        if GetResourceState('qb-core') ~= 'started' then return nil end
        local ok, core = pcall(function()
            return exports['qb-core']:GetCoreObject()
        end)
        if ok and core and core.Shared and core.Shared.Jobs and core.Shared.Jobs[jobName] then
            return core.Shared.Jobs[jobName].label or jobName
        end
        return nil
    end

    if GetResourceState('qbx_core') ~= 'started' then return nil end
    local ok, job = pcall(function()
        return exports.qbx_core:GetJob(jobName)
    end)
    if ok and job then
        return job.label or job.name or jobName
    end

    return nil
end
