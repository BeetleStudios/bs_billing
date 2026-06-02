local function L(key, ...)
    return locale(key, ...)
end

local function notify(source, key, kind, ...)
    if key == 'notify_new_bill' and Config.UseBillingNui and Config.BillingNuiAlert ~= false then
        return
    end
    TriggerClientEvent('ox_lib:notify', source, {
        description = L(key, ...),
        type = kind or 'inform'
    })
end

--- In-game toast + optional NUI alert / lb-phone push.
local function fireRecipientNewBillAlert(targetSource, billOrAmount)
    if not targetSource or targetSource < 1 then return end

    local amount = 0
    local payload = nil
    if type(billOrAmount) == 'table' then
        amount = tonumber(billOrAmount.amount) or 0
        payload = {
            amount = amount,
            billId = billOrAmount.id,
            issuerName = billOrAmount.issuer_name_snapshot,
            reason = billOrAmount.reason,
        }
    else
        amount = tonumber(billOrAmount) or 0
        payload = { amount = amount }
    end

    notify(targetSource, 'notify_new_bill', 'inform', tostring(amount))

    if Config.UseBillingNui and Config.BillingNuiAlert ~= false and payload then
        TriggerClientEvent('bs_billing:client:incomingBill', targetSource, payload)
    end

    if Config.LbPhoneBillNotify ~= false then
        TriggerClientEvent('bs_billing:client:newBillLbPhone', targetSource, amount)
    end
end

--- Issuer alert when someone pays their bill (ox_lib + optional lb-phone).
local function fireIssuerBillPaidAlert(issuerSource, bill)
    if not issuerSource or issuerSource < 1 or not bill then return end

    notify(issuerSource, 'notify_bill_paid', 'success', tostring(bill.id))

    if Config.LbPhoneBillNotify ~= false then
        TriggerClientEvent('bs_billing:client:billPaidLbPhone', issuerSource, bill.amount, bill.id)
    end
end

local function notifyBillPaidParties(payerSource, bill)
    if payerSource and payerSource > 0 then
        notify(payerSource, 'notify_paid', 'success')
    end
    if bill and bill.issuer_id then
        local issuerSource = BillingFramework.GetSourceByIdentifier(bill.issuer_id)
        if issuerSource then
            fireIssuerBillPaidAlert(issuerSource, bill)
        end
    end
end

local function makeResponse(ok, dataOrError)
    if ok then
        return { success = true, data = dataOrError }
    end
    return { success = false, error = dataOrError }
end

local function getIdentifierFromSource(source)
    local player = BillingFramework.GetPlayer(source)
    if not player then return nil end
    return BillingFramework.GetIdentifier(player), player
end

local function createBillFromSource(source, payload)
    local issuerId, issuerPlayer = getIdentifierFromSource(source)
    if not issuerId or not issuerPlayer then
        return makeResponse(false, 'issuer not found')
    end

    local targetSource = tonumber(payload.targetSource)
    if not targetSource then
        return makeResponse(false, 'invalid target source')
    end

    local targetPlayer = BillingFramework.GetPlayer(targetSource)
    if not targetPlayer then
        return makeResponse(false, 'target player offline')
    end

    local recipientId = BillingFramework.GetIdentifier(targetPlayer)
    if not recipientId then
        return makeResponse(false, 'target identifier missing')
    end

    local recipientName = BillingFramework.GetPlayerName(targetPlayer)
    local issuerName = BillingFramework.GetPlayerName(issuerPlayer)
    local issuerType = payload.issuerType == 'business' and 'business' or 'person'
    local issuerJob = nil

    if issuerType == 'business' then
        issuerJob = tostring(payload.issuerJob or '')
        if issuerJob == '' then
            local job = BillingFramework.GetPlayerJob(issuerPlayer)
            issuerJob = job and job.name or ''
        end
        if issuerJob == '' then
            return makeResponse(false, 'business job is required')
        end
        if not BillingFramework.CanCreateBusinessBill(source, issuerJob) then
            return makeResponse(false, 'no permission for business billing')
        end

        local jobLabel = BillingFramework.GetJobLabel(issuerJob)
        issuerName = tostring(jobLabel or issuerJob)
    else
        if not Config.AllowPersonalBilling then
            return makeResponse(false, 'personal billing is disabled')
        end
    end

    local created = BillingService.CreateBill({
        recipientId = recipientId,
        recipientName = recipientName,
        issuerId = issuerId,
        issuerName = issuerName,
        issuerType = issuerType,
        issuerJob = issuerJob,
        amount = payload.amount,
        reason = payload.reason
    })

    if created.success then
        notify(source, 'notify_created', 'success')
        fireRecipientNewBillAlert(targetSource, created.data)
    end

    return created
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    BillingService.EnsureTable()
end)

lib.callback.register('bs_billing:getOutstanding', function(source)
    local identifier = BillingFramework.GetIdentifier(source)
    if not identifier then
        return makeResponse(false, 'player identifier missing')
    end
    return BillingService.GetOutstandingByIdentifier(identifier)
end)

lib.callback.register('bs_billing:getHistory', function(source, limit, offset)
    local identifier = BillingFramework.GetIdentifier(source)
    if not identifier then
        return makeResponse(false, 'player identifier missing')
    end
    return BillingService.GetHistoryByIdentifier(identifier, limit, offset)
end)

lib.callback.register('bs_billing:getIssuedHistory', function(source, limit, offset)
    local identifier = BillingFramework.GetIdentifier(source)
    if not identifier then
        return makeResponse(false, 'player identifier missing')
    end
    return BillingService.GetIssuedHistoryByIdentifier(identifier, limit, offset)
end)

--- Resolve character display names for a list of server IDs (same order as input).
lib.callback.register('bs_billing:getPlayerDisplayNames', function(_, serverIds)
    if type(serverIds) ~= 'table' then
        return makeResponse(false, 'invalid request')
    end
    local maxN = 64
    local names = {}
    for i = 1, math.min(#serverIds, maxN) do
        local sid = tonumber(serverIds[i])
        if sid and sid > 0 then
            local player = BillingFramework.GetPlayer(sid)
            names[i] = player and BillingFramework.GetPlayerName(player) or ('ID %s'):format(sid)
        else
            names[i] = 'Unknown'
        end
    end
    return makeResponse(true, names)
end)

lib.callback.register('bs_billing:getContext', function(source)
    local player = BillingFramework.GetPlayer(source)
    if not player then
        return makeResponse(false, 'player not found')
    end
    local job = BillingFramework.GetPlayerJob(player)
    local jobName = job and job.name or nil
    local jobLabel = nil
    if job then
        local jl = job.label
        if type(jl) == 'string' and jl ~= '' then
            jobLabel = jl
        elseif jobName then
            jobLabel = BillingFramework.GetJobLabel(jobName)
        end
    end
    if (not jobLabel or jobLabel == '') and jobName then
        jobLabel = jobName
    end
    local canCreatePersonal = Config.AllowPersonalBilling == true
    local canCreateBusinessCurrentJob = job and BillingFramework.CanCreateBusinessBill(source, job.name) or false
    return makeResponse(true, {
        currentJob = jobName,
        currentJobLabel = jobLabel,
        canCreatePersonal = canCreatePersonal,
        canCreateBusinessCurrentJob = canCreateBusinessCurrentJob,
        canCreateAny = canCreatePersonal or canCreateBusinessCurrentJob,
        allowPersonalBilling = canCreatePersonal,
    })
end)

lib.callback.register('bs_billing:createBill', function(source, payload)
    return createBillFromSource(source, payload or {})
end)

lib.callback.register('bs_billing:payBill', function(source, billId)
    local paid = BillingService.PayBillBySource(source, tonumber(billId))
    if paid.success then
        notifyBillPaidParties(source, paid.data)
    end
    return paid
end)

lib.callback.register('bs_billing:cancelBill', function(source, billId)
    local identifier = BillingFramework.GetIdentifier(source)
    if not identifier then
        return makeResponse(false, 'player identifier missing')
    end

    local billResult = BillingService.GetBillById(tonumber(billId))
    if not billResult.success then return billResult end
    local bill = billResult.data

    local canCancel = bill.issuer_id == identifier
    if not canCancel and bill.issuer_type == 'business' and bill.issuer_job and bill.issuer_job ~= '' then
        canCancel = BillingFramework.CanCreateBusinessBill(source, bill.issuer_job)
    end
    if not canCancel then
        return makeResponse(false, 'no permission to cancel this bill')
    end

    local cancelled = BillingService.CancelBill(tonumber(billId), identifier)
    if cancelled.success then
        notify(source, 'notify_cancelled', 'success')
    end
    return cancelled
end)

if Config.EnableBillingCommand ~= false then
    RegisterCommand(Config.Command or 'billing', function(source)
        if source <= 0 then return end
        TriggerClientEvent('bs_billing:client:open', source)
    end, false)
end

-- Exports
exports('CreateBill', function(data)
    data = data or {}
    local issuerType = (data.issuerType == 'business') and 'business' or 'person'
    if issuerType == 'person' and not Config.AllowPersonalBilling then
        return makeResponse(false, 'personal billing is disabled')
    end
    local created = BillingService.CreateBill(data)
    if created.success and data.recipientId and tostring(data.recipientId) ~= '' then
        local src = BillingFramework.GetSourceByIdentifier(data.recipientId)
        fireRecipientNewBillAlert(src, created.data)
    end
    return created
end)

exports('CreatePlayerBill', function(targetSource, amount, reason, options)
    if not Config.AllowPersonalBilling then
        return makeResponse(false, 'personal billing is disabled')
    end
    targetSource = tonumber(targetSource)
    if not targetSource then return makeResponse(false, 'invalid target source') end

    local targetPlayer = BillingFramework.GetPlayer(targetSource)
    if not targetPlayer then return makeResponse(false, 'target player offline') end

    local recipientId = BillingFramework.GetIdentifier(targetPlayer)
    if not recipientId then return makeResponse(false, 'target identifier missing') end

    local opts = options or {}
    local created = BillingService.CreateBill({
        recipientId = recipientId,
        recipientName = BillingFramework.GetPlayerName(targetPlayer),
        issuerId = opts.issuerId,
        issuerName = opts.issuerName or 'External',
        issuerType = 'person',
        amount = amount,
        reason = reason
    })
    if created.success then
        fireRecipientNewBillAlert(targetSource, created.data)
    end
    return created
end)

exports('CreateBusinessBill', function(targetSource, amount, reason, jobName, options)
    targetSource = tonumber(targetSource)
    if not targetSource then return makeResponse(false, 'invalid target source') end
    if not jobName or tostring(jobName) == '' then return makeResponse(false, 'missing job name') end

    local targetPlayer = BillingFramework.GetPlayer(targetSource)
    if not targetPlayer then return makeResponse(false, 'target player offline') end

    local recipientId = BillingFramework.GetIdentifier(targetPlayer)
    if not recipientId then return makeResponse(false, 'target identifier missing') end

    local opts = options or {}
    local jobLabel = BillingFramework.GetJobLabel(tostring(jobName))
    local created = BillingService.CreateBill({
        recipientId = recipientId,
        recipientName = BillingFramework.GetPlayerName(targetPlayer),
        issuerId = opts.issuerId,
        issuerName = opts.issuerName or tostring(jobLabel or jobName),
        issuerType = 'business',
        issuerJob = tostring(jobName),
        amount = amount,
        reason = reason
    })
    if created.success then
        fireRecipientNewBillAlert(targetSource, created.data)
    end
    return created
end)

exports('GetOutstandingBillsBySource', function(source)
    local identifier = BillingFramework.GetIdentifier(tonumber(source))
    if not identifier then return makeResponse(false, 'player identifier missing') end
    return BillingService.GetOutstandingByIdentifier(identifier)
end)

exports('GetOutstandingBillsByIdentifier', function(identifier)
    return BillingService.GetOutstandingByIdentifier(identifier)
end)

exports('GetBillHistoryBySource', function(source, limit, offset)
    local identifier = BillingFramework.GetIdentifier(tonumber(source))
    if not identifier then return makeResponse(false, 'player identifier missing') end
    return BillingService.GetHistoryByIdentifier(identifier, limit, offset)
end)

exports('GetBillHistoryByIdentifier', function(identifier, limit, offset)
    return BillingService.GetHistoryByIdentifier(identifier, limit, offset)
end)

exports('GetIssuedBillHistoryBySource', function(source, limit, offset)
    local identifier = BillingFramework.GetIdentifier(tonumber(source))
    if not identifier then return makeResponse(false, 'player identifier missing') end
    return BillingService.GetIssuedHistoryByIdentifier(identifier, limit, offset)
end)

exports('GetIssuedBillHistoryByIdentifier', function(identifier, limit, offset)
    return BillingService.GetIssuedHistoryByIdentifier(identifier, limit, offset)
end)

exports('GetBillById', function(billId)
    return BillingService.GetBillById(tonumber(billId))
end)

exports('PayBill', function(source, billId)
    local payerSource = tonumber(source)
    local paid = BillingService.PayBillBySource(payerSource, tonumber(billId))
    if paid.success then
        notifyBillPaidParties(payerSource, paid.data)
    end
    return paid
end)

exports('CancelBill', function(billId, actorSource)
    local identifier = BillingFramework.GetIdentifier(tonumber(actorSource))
    if not identifier then return makeResponse(false, 'actor identifier missing') end
    return BillingService.CancelBill(tonumber(billId), identifier)
end)

exports('MarkBillPaid', function(billId, metadata)
    metadata = metadata or {}
    local paid = BillingService.MarkBillPaid(tonumber(billId), metadata.paidById, metadata.paymentSource or Config.Account or 'bank')
    if paid.success and paid.data and paid.data.issuer_id then
        local issuerSource = BillingFramework.GetSourceByIdentifier(paid.data.issuer_id)
        if issuerSource then
            fireIssuerBillPaidAlert(issuerSource, paid.data)
        end
    end
    return paid
end)
