local function L(key, ...)
    return locale(key, ...)
end

local function notify(source, key, kind, ...)
    TriggerClientEvent('ox_lib:notify', source, {
        description = L(key, ...),
        type = kind or 'inform'
    })
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
        if not Config.AllowPersonalBillByAnyone then
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
        notify(targetSource, 'notify_new_bill', 'inform', tostring(created.data.amount))
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
    return makeResponse(true, {
        currentJob = job and job.name or nil,
        canCreatePersonal = Config.AllowPersonalBillByAnyone,
        canCreateBusinessCurrentJob = job and BillingFramework.CanCreateBusinessBill(source, job.name) or false
    })
end)

lib.callback.register('bs_billing:createBill', function(source, payload)
    return createBillFromSource(source, payload or {})
end)

lib.callback.register('bs_billing:payBill', function(source, billId)
    local paid = BillingService.PayBillBySource(source, tonumber(billId))
    if paid.success then
        notify(source, 'notify_paid', 'success')

        local bill = paid.data
        if bill and bill.issuer_id then
            local issuerSource = BillingFramework.GetSourceByIdentifier(bill.issuer_id)
            if issuerSource then
                notify(issuerSource, 'notify_bill_paid', 'success', tostring(bill.id))
            end
        end
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
    return BillingService.CreateBill(data or {})
end)

exports('CreatePlayerBill', function(targetSource, amount, reason, options)
    targetSource = tonumber(targetSource)
    if not targetSource then return makeResponse(false, 'invalid target source') end

    local targetPlayer = BillingFramework.GetPlayer(targetSource)
    if not targetPlayer then return makeResponse(false, 'target player offline') end

    local recipientId = BillingFramework.GetIdentifier(targetPlayer)
    if not recipientId then return makeResponse(false, 'target identifier missing') end

    local opts = options or {}
    return BillingService.CreateBill({
        recipientId = recipientId,
        recipientName = BillingFramework.GetPlayerName(targetPlayer),
        issuerId = opts.issuerId,
        issuerName = opts.issuerName or 'External',
        issuerType = 'person',
        amount = amount,
        reason = reason
    })
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
    return BillingService.CreateBill({
        recipientId = recipientId,
        recipientName = BillingFramework.GetPlayerName(targetPlayer),
        issuerId = opts.issuerId,
        issuerName = opts.issuerName or tostring(jobLabel or jobName),
        issuerType = 'business',
        issuerJob = tostring(jobName),
        amount = amount,
        reason = reason
    })
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

exports('GetBillById', function(billId)
    return BillingService.GetBillById(tonumber(billId))
end)

exports('PayBill', function(source, billId)
    return BillingService.PayBillBySource(tonumber(source), tonumber(billId))
end)

exports('CancelBill', function(billId, actorSource)
    local identifier = BillingFramework.GetIdentifier(tonumber(actorSource))
    if not identifier then return makeResponse(false, 'actor identifier missing') end
    return BillingService.CancelBill(tonumber(billId), identifier)
end)

exports('MarkBillPaid', function(billId, metadata)
    metadata = metadata or {}
    return BillingService.MarkBillPaid(tonumber(billId), metadata.paidById, metadata.paymentSource or Config.Account or 'bank')
end)
