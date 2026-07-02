BillingNui = {}

local MANUAL_VALUE = '__bs_billing_manual_target__'
local nuiOpen = false
local alertActive = false

local function getNearbyServerIdsSorted()
    local radius = tonumber(Config.NearbyBillTargetRadius) or 25.0
    local maxEntries = tonumber(Config.NearbyBillTargetMax) or 24
    if radius <= 0 then return {} end

    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local mySid = GetPlayerServerId(PlayerId())
    local found = {}

    for _, playerIdx in ipairs(GetActivePlayers()) do
        local sid = GetPlayerServerId(playerIdx)
        if sid ~= mySid then
            local ped = GetPlayerPed(playerIdx)
            if ped and ped ~= 0 then
                local coords = GetEntityCoords(ped)
                local dist = #(myCoords - coords)
                if dist <= radius then
                    found[#found + 1] = { sid = sid, dist = dist }
                end
            end
        end
    end

    table.sort(found, function(a, b)
        return a.dist < b.dist
    end)

    local n = math.min(#found, maxEntries)
    local ids = {}
    for i = 1, n do
        ids[i] = found[i].sid
    end
    return ids
end

function BillingNui.IsOpen()
    return nuiOpen
end

function BillingNui.HasIncomingAlert()
    return alertActive
end

function BillingNui.ClearIncomingAlert()
    alertActive = false
    SendNUIMessage({ action = 'clearIncoming' })
end

function BillingNui.Open(tab)
    tab = tab or 'outstanding'
    BillingNui.ClearIncomingAlert()
    nuiOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({
        action = 'open',
        data = { tab = tab },
    })
end

function BillingNui.Close()
    if not nuiOpen then return end
    nuiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

function BillingNui.ShowIncomingBill(payload)
    if Config.BillingNuiAlert == false then return end
    if type(payload) ~= 'table' then return end

    alertActive = true
    payload.openKey = Config.NewBillAlertOpenKey or 'E'
    payload.dismissKey = Config.NewBillAlertDismissKey

    SendNUIMessage({
        action = 'incomingBill',
        data = payload,
    })
end

local function openFromNewBillAlert()
    if not alertActive or nuiOpen then return end
    BillingNui.Open('outstanding')
end

local function dismissNewBillAlert()
    if not alertActive or nuiOpen then return end
    BillingNui.ClearIncomingAlert()
end

RegisterCommand('+bs_billing_open_new_bill', openFromNewBillAlert, false)
RegisterCommand('-bs_billing_open_new_bill', function() end, false)
RegisterKeyMapping(
    '+bs_billing_open_new_bill',
    'Open new bill alert (bs_billing)',
    'keyboard',
    Config.NewBillAlertOpenKey or 'E'
)

if Config.NewBillAlertDismissKey ~= false then
    RegisterCommand('+bs_billing_dismiss_new_bill', dismissNewBillAlert, false)
    RegisterCommand('-bs_billing_dismiss_new_bill', function() end, false)
    RegisterKeyMapping(
        '+bs_billing_dismiss_new_bill',
        'Dismiss new bill alert (bs_billing)',
        'keyboard',
        Config.NewBillAlertDismissKey or 'BACK'
    )
end

RegisterNUICallback('close', function(_, cb)
    BillingNui.Close()
    cb('ok')
end)

RegisterNUICallback('dismissAlert', function(_, cb)
    BillingNui.ClearIncomingAlert()
    cb('ok')
end)

RegisterNUICallback('getOutstanding', function(_, cb)
    cb(lib.callback.await('bs_billing:getOutstanding', false) or { success = false })
end)

RegisterNUICallback('getHistory', function(data, cb)
    local limit = data and tonumber(data.limit) or 50
    local offset = data and tonumber(data.offset) or 0
    cb(lib.callback.await('bs_billing:getHistory', false, limit, offset) or { success = false })
end)

RegisterNUICallback('getIssuedHistory', function(data, cb)
    local limit = data and tonumber(data.limit) or 50
    local offset = data and tonumber(data.offset) or 0
    cb(lib.callback.await('bs_billing:getIssuedHistory', false, limit, offset) or { success = false })
end)

RegisterNUICallback('payBill', function(data, cb)
    local billId = data and tonumber(data.billId)
    if not billId then
        cb({ success = false, error = 'invalid bill id' })
        return
    end
    cb(lib.callback.await('bs_billing:payBill', false, billId) or { success = false })
end)

RegisterNUICallback('cancelBill', function(data, cb)
    local billId = data and tonumber(data.billId)
    if not billId then
        cb({ success = false, error = 'invalid bill id' })
        return
    end
    cb(lib.callback.await('bs_billing:cancelBill', false, billId) or { success = false })
end)

RegisterNUICallback('getContext', function(_, cb)
    cb(lib.callback.await('bs_billing:getContext', false) or { success = false })
end)

RegisterNUICallback('createBill', function(data, cb)
    local payload = data and data.payload
    if type(payload) ~= 'table' then
        cb({ success = false, error = 'invalid payload' })
        return
    end
    cb(lib.callback.await('bs_billing:createBill', false, payload) or { success = false })
end)

RegisterNUICallback('getCreateTargets', function(_, cb)
    local nearbyIds = getNearbyServerIdsSorted()
    local options = {}

    if #nearbyIds > 0 then
        local nameResult = lib.callback.await('bs_billing:getPlayerDisplayNames', false, nearbyIds)
        local names = (nameResult and nameResult.success and nameResult.data) or {}
        for i = 1, #nearbyIds do
            local sid = nearbyIds[i]
            local nm = names[i] or '?'
            options[#options + 1] = {
                value = tostring(sid),
                label = ('Server Id #%s - %s'):format(sid, nm),
            }
        end
    end

    options[#options + 1] = {
        value = MANUAL_VALUE,
        label = 'Manual server ID…',
    }

    cb({ success = true, options = options, manualValue = MANUAL_VALUE })
end)

RegisterNUICallback('getLang', function(_, cb)
    local lang = GetConvar('ox:locale', 'en')
    if type(lang) ~= 'string' or lang == '' then
        lang = 'en'
    end
    cb({ lang = lang })
end)

RegisterNUICallback('uiNotify', function(data, cb)
    lib.notify({
        title = data and data.title or locale('menu_title'),
        description = data and data.description or '',
        type = data and data.type or 'inform',
    })
    cb('ok')
end)

RegisterNUICallback('getBusinessOutstanding', function(_, cb)
    cb(lib.callback.await('bs_billing:getBusinessOutstanding', false) or { success = false })
end)

RegisterNUICallback('getBusinessBillTrend', function(data, cb)
    local period = data and data.period or 'day'
    cb(lib.callback.await('bs_billing:getBusinessBillTrend', false, period) or { success = false })
end)

RegisterNUICallback('getBusinessIssuerLeaderboard', function(_, cb)
    cb(lib.callback.await('bs_billing:getBusinessIssuerLeaderboard', false) or { success = false })
end)

RegisterNUICallback('remindBill', function(data, cb)
    local billId = data and tonumber(data.billId)
    if not billId then
        cb({ success = false, error = 'invalid bill id' })
        return
    end
    cb(lib.callback.await('bs_billing:remindBill', false, billId) or { success = false })
end)
