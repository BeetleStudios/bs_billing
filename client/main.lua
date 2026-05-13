local function L(key, ...)
    return locale(key, ...)
end

local function notifyError(message)
    lib.notify({
        type = 'error',
        description = L('notify_error', message or 'unknown')
    })
end

local function formatDateTime(value)
    if value == nil then return 'N/A' end
    return tostring(value)
end

local function getBillCreatedValue(bill)
    if not bill then return nil end
    if bill.created_at ~= nil then return bill.created_at end
    if bill.createdAt ~= nil then return bill.createdAt end
    if bill.created ~= nil then
        if type(bill.created) == 'table' and bill.created.at ~= nil then
            return bill.created.at
        end
        return bill.created
    end
    return nil
end

local function getBillIssuerLabel(bill)
    local name = bill and bill.issuer_name_snapshot
    if name and tostring(name) ~= '' then
        return tostring(name)
    end
    local job = bill and bill.issuer_job
    if job and tostring(job) ~= '' then
        return tostring(job)
    end
    return 'Unknown'
end

local function requestOutstanding()
    return lib.callback.await('bs_billing:getOutstanding', false)
end

local function requestHistory(limit, offset)
    return lib.callback.await('bs_billing:getHistory', false, limit, offset)
end

local function requestIssuedHistory(limit, offset)
    return lib.callback.await('bs_billing:getIssuedHistory', false, limit, offset)
end

local function payBill(bill)
    local confirm = lib.alertDialog({
        header = L('confirm_pay_title'),
        content = L('confirm_pay_desc', tostring(bill.amount), bill.reason),
        centered = true,
        cancel = true,
        labels = {
            cancel = L('confirm_no'),
            confirm = L('confirm_yes')
        }
    })

    if confirm ~= 'confirm' then return end

    local result = lib.callback.await('bs_billing:payBill', false, bill.id)
    if not result or not result.success then
        notifyError(result and result.error or 'pay failed')
        return
    end

    lib.notify({ type = 'success', description = L('notify_paid') })
end

local function cancelBill(bill)
    local result = lib.callback.await('bs_billing:cancelBill', false, bill.id)
    if not result or not result.success then
        notifyError(result and result.error or 'cancel failed')
        return
    end
    lib.notify({ type = 'success', description = L('notify_cancelled') })
end

local MANUAL_TARGET = '__bs_billing_manual_target__'

--- Closest other players when the dialog opens (client ped positions).
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

local function getBillRecipientLabel(bill)
    local name = bill and bill.recipient_name_snapshot
    if name and tostring(name) ~= '' then
        return tostring(name)
    end
    return 'Unknown'
end

local function openHistoryListView(mode)
    local result = (mode == 'issued') and requestIssuedHistory(100, 0) or requestHistory(100, 0)
    if not result or not result.success then
        return notifyError(result and result.error or 'history fetch failed')
    end

    local options = {}
    local bills = result.data or {}

    if #bills == 0 then
        options[#options + 1] = { title = L('menu_none'), disabled = true }
    else
        for i = 1, #bills do
            local bill = bills[i]
            local whoLine
            if mode == 'issued' then
                whoLine = L('bill_to', getBillRecipientLabel(bill), tostring(bill.reason or ''))
            else
                whoLine = L('bill_from', getBillIssuerLabel(bill), tostring(bill.reason or ''))
            end
            options[#options + 1] = {
                title = ('#%s - $%s'):format(bill.id, bill.amount),
                description = ('[%s] %s | %s'):format(
                    tostring(bill.status),
                    whoLine,
                    formatDateTime(getBillCreatedValue(bill))
                ),
                disabled = true
            }
        end
    end

    local title = mode == 'issued' and L('history_title_issued') or L('history_title_received')
    local ctxId = mode == 'issued' and 'bs_billing_history_issued' or 'bs_billing_history_received'

    lib.registerContext({
        id = ctxId,
        title = title,
        menu = 'bs_billing_history_menu',
        options = options
    })
    lib.showContext(ctxId)
end

local function openHistoryMenu()
    lib.registerContext({
        id = 'bs_billing_history_menu',
        title = L('menu_history'),
        menu = 'bs_billing_main',
        options = {
            {
                title = L('history_hub_received'),
                description = L('history_hub_received_desc'),
                arrow = true,
                onSelect = function()
                    openHistoryListView('received')
                end
            },
            {
                title = L('history_hub_issued'),
                description = L('history_hub_issued_desc'),
                arrow = true,
                onSelect = function()
                    openHistoryListView('issued')
                end
            }
        }
    })
    lib.showContext('bs_billing_history_menu')
end

local function openCreateDialog()
    local contextResult = lib.callback.await('bs_billing:getContext', false)
    if not contextResult or not contextResult.success then
        return notifyError(contextResult and contextResult.error or 'context fetch failed')
    end
    local context = contextResult.data or {}

    local nearbyIds = getNearbyServerIdsSorted()
    local nameResult = nearbyIds[1] and lib.callback.await('bs_billing:getPlayerDisplayNames', false, nearbyIds)
    local names = (nameResult and nameResult.success and nameResult.data) or {}

    local targetOptions = {}
    for i = 1, #nearbyIds do
        local sid = nearbyIds[i]
        local nm = names[i] or 'Unknown'
        targetOptions[#targetOptions + 1] = {
            value = sid,
            label = L('create_target_nearby_row', sid, nm)
        }
    end
    targetOptions[#targetOptions + 1] = {
        value = MANUAL_TARGET,
        label = L('create_target_manual')
    }

    local defaultTarget = targetOptions[1] and targetOptions[1].value or MANUAL_TARGET

    local input = lib.inputDialog(L('create_title'), {
        {
            type = 'select',
            label = L('create_target'),
            description = L('create_target_help'),
            required = true,
            default = defaultTarget,
            options = targetOptions
        },
        {
            type = 'number',
            label = L('create_target_manual_id'),
            description = L('create_target_manual_hint'),
            required = false,
            min = 1,
            step = 1
        },
        { type = 'number', label = L('create_amount'), required = true, min = 1, step = 1 },
        { type = 'input', label = L('create_reason'), required = true, max = Config.MaxReasonLength or 120 },
        {
            type = 'select',
            label = L('create_type'),
            required = true,
            options = {
                { value = 'person', label = L('create_type_personal') },
                { value = 'business', label = L('create_type_business') }
            }
        },
    })

    if not input then return end

    local issuerType = tostring(input[5])
    if issuerType == 'business' and (not context.currentJob or tostring(context.currentJob) == '') then
        return notifyError(L('create_business_need_job'))
    end

    local targetPick = input[1]
    local manualPick = targetPick == MANUAL_TARGET or tostring(targetPick) == MANUAL_TARGET
    local targetSource = nil
    if manualPick then
        targetSource = tonumber(input[2])
        if not targetSource then
            return notifyError(L('create_target_manual_required'))
        end
    else
        targetSource = tonumber(targetPick)
    end

    if not targetSource or targetSource < 1 then
        return notifyError(L('create_target_invalid'))
    end

    local payload = {
        targetSource = targetSource,
        amount = tonumber(input[3]),
        reason = tostring(input[4]),
        issuerType = issuerType,
        issuerJob = issuerType == 'business' and (context.currentJob or '') or '',
    }

    local result = lib.callback.await('bs_billing:createBill', false, payload)
    if not result or not result.success then
        return notifyError(result and result.error or 'create failed')
    end

    lib.notify({ type = 'success', description = L('notify_created') })
end

local function openOutstandingMenu()
    local result = requestOutstanding()
    if not result or not result.success then
        return notifyError(result and result.error or 'outstanding fetch failed')
    end

    local options = {}
    local bills = result.data or {}

    if #bills == 0 then
        options[#options + 1] = { title = L('menu_none'), disabled = true }
    else
        for i = 1, #bills do
            local bill = bills[i]
            options[#options + 1] = {
                title = ('#%s - $%s'):format(bill.id, bill.amount),
                description = ('From: %s | %s | %s'):format(
                    getBillIssuerLabel(bill),
                    tostring(bill.reason or ''),
                    formatDateTime(getBillCreatedValue(bill))
                ),
                onSelect = function()
                    local action = lib.inputDialog(('Bill #%s'):format(bill.id), {
                        {
                            type = 'select',
                            label = 'Action',
                            options = {
                                { value = 'pay', label = 'Pay' },
                                { value = 'cancel', label = 'Cancel (issuer only)' }
                            },
                            required = true
                        }
                    })

                    if not action then return end
                    if action[1] == 'pay' then
                        payBill(bill)
                    elseif action[1] == 'cancel' then
                        cancelBill(bill)
                    end
                end
            }
        end
    end

    lib.registerContext({
        id = 'bs_billing_outstanding',
        title = L('menu_outstanding'),
        menu = 'bs_billing_main',
        options = options
    })
    lib.showContext('bs_billing_outstanding')
end

local function openMainMenu()
    lib.registerContext({
        id = 'bs_billing_main',
        title = L('menu_title'),
        options = {
            {
                title = L('menu_outstanding'),
                onSelect = openOutstandingMenu
            },
            {
                title = L('menu_history'),
                onSelect = openHistoryMenu
            },
            {
                title = L('menu_create'),
                onSelect = openCreateDialog
            }
        }
    })

    lib.showContext('bs_billing_main')
end

RegisterNetEvent('bs_billing:client:open', function()
    openMainMenu()
end)

--- Open the ox_lib billing context menu (Outstanding / History / Create).
exports('OpenMainMenu', openMainMenu)

if Config.EnableBillingCommand ~= false then
    RegisterCommand(Config.Command or 'billing', function()
        openMainMenu()
    end, false)
end

RegisterNetEvent('bs_billing:client:newBillLbPhone', function(amount)
    if GetResourceState('lb-phone') ~= 'started' then return end
    amount = tonumber(amount) or 0
    pcall(function()
        exports['lb-phone']:SendNotification({
            app = Config.LbPhoneBillAppIdentifier or 'Billing',
            title = L('menu_title'),
            content = L('notify_new_bill', tostring(amount)),
        })
    end)
end)
