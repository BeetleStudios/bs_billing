BillingService = {}

local function query(sql, params)
    return MySQL.query.await(sql, params or {})
end

local function insert(sql, params)
    return MySQL.insert.await(sql, params or {})
end

local function update(sql, params)
    return MySQL.update.await(sql, params or {})
end

local function nowDateTime()
    return os.date('%Y-%m-%d %H:%M:%S')
end

local function formatReadableDate(value)
    if value == nil then return nil end

    local function formatEpochNumber(epoch)
        epoch = math.floor(tonumber(epoch) or 0)
        if epoch <= 0 then return nil end
        return os.date('%m/%d/%Y %I:%M %p', epoch)
    end

    if type(value) == 'string' then
        local raw = value:gsub('^%s+', ''):gsub('%s+$', '')

        -- Numeric epoch-like values from DB (seconds/ms/us/ns).
        if raw:match('^%d+$') then
            local n = tonumber(raw)
            local digits = #raw
            if digits >= 19 then
                n = math.floor(n / 1000000000) -- ns -> s
            elseif digits >= 16 then
                n = math.floor(n / 1000000) -- us -> s
            elseif digits >= 13 then
                n = math.floor(n / 1000) -- ms -> s
            end
            local out = formatEpochNumber(n)
            if out then
                return out
            end
        end

        local y, m, d, hh, mm, ss = value:match('^(%d+)%-(%d+)%-(%d+)%s+(%d+):(%d+):(%d+)$')
        if y and m and d and hh and mm and ss then
            local year = tonumber(y)
            local month = tonumber(m)
            local day = tonumber(d)
            local hour = tonumber(hh)
            local minute = tonumber(mm)
            local second = tonumber(ss)
            if not year or not month or not day or not hour or not minute or not second then
                return tostring(value)
            end
            local epoch = os.time({
                year = year,
                month = month,
                day = day,
                hour = hour,
                min = minute,
                sec = second
            })
            if epoch then
                return os.date('%m/%d/%Y %I:%M %p', epoch)
            end
        end
    elseif type(value) == 'number' then
        local n = value
        if n > 1000000000000000000 then
            n = math.floor(n / 1000000000) -- ns -> s
        elseif n > 1000000000000000 then
            n = math.floor(n / 1000000) -- us -> s
        elseif n > 1000000000000 then
            n = math.floor(n / 1000) -- ms -> s
        end
        local out = formatEpochNumber(n)
        if out then
            return out
        end
    end

    return tostring(value)
end

local function normalizeBillRow(row)
    if not row then return row end
    row.created_at = formatReadableDate(row.created_at)
    row.updated_at = formatReadableDate(row.updated_at)
    row.paid_at = formatReadableDate(row.paid_at)
    row.cancelled_at = formatReadableDate(row.cancelled_at)
    return row
end

local function normalizeBillRows(rows)
    rows = rows or {}
    for i = 1, #rows do
        normalizeBillRow(rows[i])
    end
    return rows
end

local function clampAmount(amount)
    amount = tonumber(amount)
    if not amount then return nil end
    amount = math.floor(amount)
    if amount < (Config.MinAmount or 1) then return nil end
    if amount > (Config.MaxAmount or 1000000) then return nil end
    return amount
end

local function sanitizeReason(reason)
    reason = tostring(reason or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if reason == '' then return nil end
    local maxLen = Config.MaxReasonLength or 120
    if #reason > maxLen then
        reason = reason:sub(1, maxLen)
    end
    return reason
end

local function getBusinessCommissionRate(jobName)
    if not jobName or jobName == '' then return 0 end
    local t = Config.BusinessCommissionPercent
    if type(t) ~= 'table' then return 0 end
    local r = t[jobName]
    if r == nil then return 0 end
    r = tonumber(r) or 0
    if r < 0 then r = 0 end
    if r > 1 then r = 1 end
    return r
end

--- Society gets (total - commission); commission goes to issuer bank by identifier (online or offline when supported), else to society.
--- Returns ok, errMessage
local function payBusinessBillSplits(bill, total)
    local job = bill.issuer_job
    local rate = getBusinessCommissionRate(job)
    local commission = math.floor(tonumber(total) * rate + 1e-9)
    if commission < 0 then commission = 0 end
    if commission > total then commission = total end
    local societyAmount = total - commission

    if societyAmount > 0 then
        if not BillingBanking.AddJobMoney(job, societyAmount) then
            return false, 'failed to deposit society account'
        end
    end

    if commission <= 0 then
        return true
    end

    if bill.issuer_id and bill.issuer_id ~= '' then
        if BillingFramework.AddMoneyByIdentifier(bill.issuer_id, Config.Account or 'bank', commission, 'bs_billing:business_commission') then
            return true
        end
    end

    if BillingBanking.AddJobMoney(job, commission) then
        return true
    end

    if societyAmount > 0 then
        BillingBanking.RemoveJobMoney(job, societyAmount)
    end
    return false, 'failed to pay business commission'
end

function BillingService.EnsureTable()
    query([[
        CREATE TABLE IF NOT EXISTS `bs_billing_invoices` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `recipient_id` VARCHAR(80) NOT NULL,
            `recipient_name_snapshot` VARCHAR(100) NOT NULL,
            `issuer_id` VARCHAR(80) NULL,
            `issuer_name_snapshot` VARCHAR(100) NOT NULL,
            `issuer_type` VARCHAR(20) NOT NULL DEFAULT 'person',
            `issuer_job` VARCHAR(80) NULL,
            `amount` INT NOT NULL,
            `reason` VARCHAR(255) NOT NULL,
            `status` VARCHAR(20) NOT NULL DEFAULT 'outstanding',
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            `paid_at` DATETIME NULL,
            `paid_by_id` VARCHAR(80) NULL,
            `payment_source` VARCHAR(20) NULL,
            `cancelled_at` DATETIME NULL,
            `cancelled_by_id` VARCHAR(80) NULL,
            PRIMARY KEY (`id`),
            INDEX `idx_recipient_status_created` (`recipient_id`, `status`, `created_at`),
            INDEX `idx_recipient_created` (`recipient_id`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})
end

function BillingService.CreateBill(data)
    local recipientId = data and data.recipientId or nil
    local recipientName = data and data.recipientName or nil
    local issuerId = data and data.issuerId or nil
    local issuerName = data and data.issuerName or 'Unknown'
    local issuerType = (data and data.issuerType) or 'person'
    local issuerJob = data and data.issuerJob or nil
    local amount = clampAmount(data and data.amount)
    local reason = sanitizeReason(data and data.reason)

    if not recipientId then
        return { success = false, error = 'missing recipient identifier' }
    end
    if not recipientName then
        recipientName = 'Unknown'
    end
    if issuerType ~= 'person' and issuerType ~= 'business' then
        return { success = false, error = 'invalid issuer type' }
    end
    if not amount then
        return { success = false, error = 'invalid amount' }
    end
    if not reason then
        return { success = false, error = 'invalid reason' }
    end
    if issuerType == 'business' and (not issuerJob or issuerJob == '') then
        return { success = false, error = 'missing business job' }
    end

    local id = insert([[
        INSERT INTO bs_billing_invoices
        (recipient_id, recipient_name_snapshot, issuer_id, issuer_name_snapshot, issuer_type, issuer_job, amount, reason, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'outstanding')
    ]], {
        recipientId, recipientName, issuerId, issuerName, issuerType, issuerJob, amount, reason
    })

    if not id then
        return { success = false, error = 'database insert failed' }
    end

    return BillingService.GetBillById(id)
end

function BillingService.GetBillById(billId)
    local rows = query('SELECT * FROM bs_billing_invoices WHERE id = ? LIMIT 1', { billId })
    local bill = rows and rows[1] or nil
    if not bill then
        return { success = false, error = 'bill not found' }
    end
    normalizeBillRow(bill)
    return { success = true, data = bill }
end

function BillingService.GetOutstandingByIdentifier(identifier)
    if not identifier then
        return { success = false, error = 'missing identifier' }
    end
    local rows = query([[
        SELECT * FROM bs_billing_invoices
        WHERE recipient_id = ? AND status = 'outstanding'
        ORDER BY created_at DESC
    ]], { identifier })
    return { success = true, data = normalizeBillRows(rows) }
end

function BillingService.GetHistoryByIdentifier(identifier, limit, offset)
    if not identifier then
        return { success = false, error = 'missing identifier' }
    end
    limit = tonumber(limit) or (Config.HistoryPageSize or 25)
    offset = tonumber(offset) or 0
    if limit < 1 then limit = 1 end
    if limit > 100 then limit = 100 end
    if offset < 0 then offset = 0 end

    local rows = query([[
        SELECT * FROM bs_billing_invoices
        WHERE recipient_id = ?
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
    ]], { identifier, limit, offset })

    return { success = true, data = normalizeBillRows(rows) }
end

function BillingService.CancelBill(billId, actorIdentifier)
    local billResult = BillingService.GetBillById(billId)
    if not billResult.success then
        return billResult
    end

    local bill = billResult.data
    if bill.status ~= 'outstanding' then
        return { success = false, error = 'bill is not outstanding' }
    end

    local changed = update([[
        UPDATE bs_billing_invoices
        SET status = 'cancelled', cancelled_at = ?, cancelled_by_id = ?
        WHERE id = ? AND status = 'outstanding'
    ]], { nowDateTime(), actorIdentifier, billId })

    if not changed or changed < 1 then
        return { success = false, error = 'cancel update failed' }
    end

    return BillingService.GetBillById(billId)
end

function BillingService.MarkBillPaid(billId, paidByIdentifier, paymentSource)
    local changed = update([[
        UPDATE bs_billing_invoices
        SET status = 'paid', paid_at = ?, paid_by_id = ?, payment_source = ?
        WHERE id = ? AND status = 'outstanding'
    ]], { nowDateTime(), paidByIdentifier, paymentSource, billId })

    if not changed or changed < 1 then
        return { success = false, error = 'pay update failed' }
    end

    return BillingService.GetBillById(billId)
end

function BillingService.PayBillBySource(source, billId)
    local payer = BillingFramework.GetPlayer(source)
    if not payer then
        return { success = false, error = 'payer not found' }
    end

    local payerIdentifier = BillingFramework.GetIdentifier(payer)
    if not payerIdentifier then
        return { success = false, error = 'payer identifier missing' }
    end

    local billResult = BillingService.GetBillById(billId)
    if not billResult.success then
        return billResult
    end
    local bill = billResult.data

    if bill.status ~= 'outstanding' then
        return { success = false, error = 'bill is not outstanding' }
    end
    if not Config.AllowThirdPartyPayments and bill.recipient_id ~= payerIdentifier then
        return { success = false, error = 'bill does not belong to player' }
    end

    local balance = BillingFramework.GetMoney(payer, Config.Account or 'bank')
    if balance < bill.amount then
        return { success = false, error = 'insufficient funds' }
    end

    local removed = BillingFramework.RemoveMoney(payer, Config.Account or 'bank', bill.amount, 'bs_billing:pay_bill')
    if not removed then
        return { success = false, error = 'failed to remove bank money' }
    end

    if bill.issuer_type == 'business' then
        if not bill.issuer_job or bill.issuer_job == '' then
            BillingFramework.AddMoney(payer, Config.Account or 'bank', bill.amount, 'bs_billing:refund_missing_job')
            return { success = false, error = 'bill missing business account' }
        end

        local splitOk, splitErr = payBusinessBillSplits(bill, bill.amount)
        if not splitOk then
            BillingFramework.AddMoney(payer, Config.Account or 'bank', bill.amount, 'bs_billing:refund_business_payout_failed')
            return { success = false, error = splitErr or 'failed to deposit business payout' }
        end
    elseif bill.issuer_id and bill.issuer_id ~= '' then
        local issuerSource = BillingFramework.GetSourceByIdentifier(bill.issuer_id)
        if issuerSource then
            BillingFramework.AddMoney(issuerSource, Config.Account or 'bank', bill.amount, 'bs_billing:issuer_payout')
        end
    end

    local paid = BillingService.MarkBillPaid(bill.id, payerIdentifier, Config.Account or 'bank')
    if not paid.success then
        BillingFramework.AddMoney(payer, Config.Account or 'bank', bill.amount, 'bs_billing:refund_mark_paid_failed')
        return paid
    end

    return paid
end
