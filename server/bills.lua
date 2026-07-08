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
    if row.issuer_type == 'business' and row.issuer_job and row.issuer_job ~= '' then
        local label = BillingFramework.GetJobLabel(row.issuer_job)
        if label and label ~= '' then
            local snap = row.issuer_name_snapshot
            if not snap or snap == '' or snap == row.issuer_job then
                row.issuer_name_snapshot = label
            end
        end
    end
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

local payLocks = {}

local function tryAcquirePayLock(billId)
    if payLocks[billId] then return false end
    payLocks[billId] = true
    return true
end

local function releasePayLock(billId)
    payLocks[billId] = nil
end

local function reverseBusinessPayout(ledger)
    if not ledger or not ledger.job then return end
    if ledger.societyAmount and ledger.societyAmount > 0 then
        BillingBanking.RemoveJobMoney(ledger.job, ledger.societyAmount)
    end
    if ledger.issuerCommission and ledger.issuerCommission > 0 and ledger.issuerId then
        BillingFramework.RemoveMoneyByIdentifier(
            ledger.issuerId,
            Config.Account or 'bank',
            ledger.issuerCommission,
            'bs_billing:refund_business_commission'
        )
    end
end

--- Society gets (total - commission); commission goes to issuer bank by identifier (online or offline when supported), else to society.
--- Returns ok, errMessage, ledger (for rollback)
local function payBusinessBillSplits(bill, total)
    local job = bill.issuer_job
    local rate = getBusinessCommissionRate(job)
    local commission = math.floor(tonumber(total) * rate + 1e-9)
    if commission < 0 then commission = 0 end
    if commission > total then commission = total end
    local societyAmount = total - commission

    local ledger = {
        job = job,
        societyAmount = 0,
        issuerCommission = 0,
        issuerId = bill.issuer_id,
    }

    if societyAmount > 0 then
        if not BillingBanking.AddJobMoney(job, societyAmount) then
            return false, 'failed to deposit society account', nil
        end
        ledger.societyAmount = societyAmount
    end

    if commission <= 0 then
        return true, nil, ledger
    end

    if bill.issuer_id and bill.issuer_id ~= '' then
        if BillingFramework.AddMoneyByIdentifier(bill.issuer_id, Config.Account or 'bank', commission, 'bs_billing:business_commission') then
            ledger.issuerCommission = commission
            return true, nil, ledger
        end
    end

    if BillingBanking.AddJobMoney(job, commission) then
        ledger.societyAmount = ledger.societyAmount + commission
        return true, nil, ledger
    end

    reverseBusinessPayout(ledger)
    return false, 'failed to pay business commission', nil
end

local function rollbackFailedPayment(payer, billId, amount, ledger, personalIssuerPaid)
    local account = Config.Account or 'bank'
    if ledger then
        reverseBusinessPayout(ledger)
    end
    if personalIssuerPaid and personalIssuerPaid.issuerId and personalIssuerPaid.amount and personalIssuerPaid.amount > 0 then
        BillingFramework.RemoveMoneyByIdentifier(
            personalIssuerPaid.issuerId,
            account,
            personalIssuerPaid.amount,
            'bs_billing:refund_issuer_payout'
        )
    end
    BillingFramework.AddMoney(payer, account, amount, 'bs_billing:refund_pay_failed')
    BillingService.RevertBillToOutstanding(billId)
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
    -- Help issued-history queries (safe if index already exists).
    pcall(function()
        query([[
            ALTER TABLE `bs_billing_invoices`
            ADD INDEX `idx_issuer_created` (`issuer_id`, `created_at`)
        ]], {})
    end)
    pcall(function()
        query([[
            ALTER TABLE `bs_billing_invoices`
            ADD INDEX `idx_business_job_status` (`issuer_job`, `issuer_type`, `status`)
        ]], {})
    end)
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

    if issuerType == 'business' and issuerJob and issuerJob ~= '' then
        local label = BillingFramework.GetJobLabel(issuerJob)
        if label and label ~= '' then
            if not issuerName or issuerName == '' or issuerName == 'Unknown' or issuerName == issuerJob then
                issuerName = label
            end
        end
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

function BillingService.GetIssuedHistoryByIdentifier(identifier, limit, offset)
    if not identifier or identifier == '' then
        return { success = false, error = 'missing identifier' }
    end
    limit = tonumber(limit) or (Config.HistoryPageSize or 25)
    offset = tonumber(offset) or 0
    if limit < 1 then limit = 1 end
    if limit > 100 then limit = 100 end
    if offset < 0 then offset = 0 end

    local rows = query([[
        SELECT * FROM bs_billing_invoices
        WHERE issuer_id = ?
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
    ]], { identifier, limit, offset })

    return { success = true, data = normalizeBillRows(rows) }
end

local function parseDbEpoch(value)
    if value == nil then return nil end
    if type(value) == 'number' then
        local n = math.floor(value)
        if n > 1000000000000000000 then
            n = math.floor(n / 1000000000)
        elseif n > 1000000000000000 then
            n = math.floor(n / 1000000)
        elseif n > 1000000000000 then
            n = math.floor(n / 1000)
        end
        return n > 0 and n or nil
    end
    if type(value) ~= 'string' then return nil end
    local raw = value:gsub('^%s+', ''):gsub('%s+$', '')
    if raw:match('^%d+$') then
        return parseDbEpoch(tonumber(raw))
    end
    local y, m, d, hh, mm, ss = raw:match('^(%d+)%-(%d+)%-(%d+)%s+(%d+):(%d+):(%d+)$')
    if y then
        return os.time({
            year = tonumber(y),
            month = tonumber(m),
            day = tonumber(d),
            hour = tonumber(hh),
            min = tonumber(mm),
            sec = tonumber(ss),
        })
    end
    return nil
end

local function startOfLocalDay(epoch)
    local t = os.date('*t', epoch)
    t.hour, t.min, t.sec = 0, 0, 0
    return os.time(t)
end

local function startOfLocalWeek(epoch)
    local t = os.date('*t', epoch)
    local wday = t.wday
    local daysFromMonday = (wday + 5) % 7
    local dayStart = startOfLocalDay(epoch)
    return dayStart - (daysFromMonday * 86400)
end

local function startOfLocalMonth(epoch)
    local t = os.date('*t', epoch)
    t.day, t.hour, t.min, t.sec = 1, 0, 0, 0
    return os.time(t)
end

function BillingService.GetBusinessOutstandingByJob(jobName)
    if not jobName or jobName == '' then
        return { success = false, error = 'missing job name' }
    end

    local rows = query([[
        SELECT * FROM bs_billing_invoices
        WHERE issuer_type = 'business' AND issuer_job = ? AND status = 'outstanding'
        ORDER BY created_at DESC
    ]], { jobName })

    return { success = true, data = normalizeBillRows(rows) }
end

function BillingService.GetBusinessBillTrend(jobName, period)
    if not jobName or jobName == '' then
        return { success = false, error = 'missing job name' }
    end

    period = period or 'day'
    local bucketCount = ({ day = 7, week = 4, month = 6 })[period] or 7
    local now = os.time()
    local buckets = {}

    for i = bucketCount - 1, 0, -1 do
        local startTs
        local label
        if period == 'week' then
            startTs = startOfLocalWeek(now) - (i * 7 * 86400)
            label = os.date('%m/%d', startTs)
        elseif period == 'month' then
            local t = os.date('*t', now)
            t.day, t.hour, t.min, t.sec = 1, 0, 0, 0
            t.month = t.month - i
            while t.month < 1 do
                t.month = t.month + 12
                t.year = t.year - 1
            end
            startTs = os.time(t)
            label = os.date('%b %Y', startTs)
        else
            startTs = startOfLocalDay(now) - (i * 86400)
            label = os.date('%m/%d', startTs)
        end

        local endTs
        if period == 'week' then
            endTs = startTs + (7 * 86400)
        elseif period == 'month' then
            local t = os.date('*t', startTs)
            t.month = t.month + 1
            if t.month > 12 then
                t.month = 1
                t.year = t.year + 1
            end
            endTs = os.time(t)
        else
            endTs = startTs + 86400
        end

        buckets[#buckets + 1] = {
            label = label,
            startTs = startTs,
            endTs = endTs,
            paidCount = 0,
            paidSum = 0,
            outstandingCount = 0,
            outstandingSum = 0,
        }
    end

    if #buckets == 0 then
        return { success = true, data = { period = period, buckets = {} } }
    end

    local rangeStart = os.date('%Y-%m-%d %H:%M:%S', buckets[1].startTs)
    local paidRows = query([[
        SELECT paid_at, amount FROM bs_billing_invoices
        WHERE issuer_type = 'business' AND issuer_job = ? AND status = 'paid'
          AND paid_at IS NOT NULL AND paid_at >= ?
    ]], { jobName, rangeStart }) or {}

    local outRows = query([[
        SELECT created_at, amount FROM bs_billing_invoices
        WHERE issuer_type = 'business' AND issuer_job = ? AND status = 'outstanding'
          AND created_at >= ?
    ]], { jobName, rangeStart }) or {}

    local function assignToBucket(ts, fieldCount, fieldSum, amount)
        if not ts then return end
        for i = 1, #buckets do
            local b = buckets[i]
            if ts >= b.startTs and ts < b.endTs then
                b[fieldCount] = b[fieldCount] + 1
                b[fieldSum] = b[fieldSum] + (tonumber(amount) or 0)
                return
            end
        end
    end

    for i = 1, #paidRows do
        local row = paidRows[i]
        assignToBucket(parseDbEpoch(row.paid_at), 'paidCount', 'paidSum', row.amount)
    end

    for i = 1, #outRows do
        local row = outRows[i]
        assignToBucket(parseDbEpoch(row.created_at), 'outstandingCount', 'outstandingSum', row.amount)
    end

    local out = {}
    for i = 1, #buckets do
        local b = buckets[i]
        out[i] = {
            label = b.label,
            paidCount = b.paidCount,
            paidSum = b.paidSum,
            outstandingCount = b.outstandingCount,
            outstandingSum = b.outstandingSum,
        }
    end

    return { success = true, data = { period = period, buckets = out } }
end

function BillingService.GetBusinessIssuerLeaderboard(jobName, workers)
    if not jobName or jobName == '' then
        return { success = false, error = 'missing job name' }
    end
    if type(workers) ~= 'table' or #workers == 0 then
        return { success = true, data = {} }
    end

    local maxWorkers = 128
    local n = math.min(#workers, maxWorkers)
    local placeholders = {}
    local params = { jobName }
    local nameById = {}

    for i = 1, n do
        local worker = workers[i]
        local identifier = worker and worker.identifier
        if identifier and identifier ~= '' then
            placeholders[#placeholders + 1] = '?'
            params[#params + 1] = identifier
            nameById[identifier] = (worker.name and worker.name ~= '') and worker.name or 'Unknown'
        end
    end

    if #placeholders == 0 then
        return { success = true, data = {} }
    end

    local sql = ([[
        SELECT issuer_id,
               COUNT(*) AS bill_count,
               COALESCE(SUM(amount), 0) AS bill_sum
        FROM bs_billing_invoices
        WHERE issuer_type = 'business'
          AND issuer_job = ?
          AND issuer_id IN (%s)
        GROUP BY issuer_id
        ORDER BY bill_sum DESC, bill_count DESC
        LIMIT 1000
    ]]):format(table.concat(placeholders, ','))

    local rows = query(sql, params) or {}
    local out = {}
    for i = 1, #rows do
        local row = rows[i]
        local issuerId = row.issuer_id
        out[i] = {
            issuerId = issuerId,
            issuerName = nameById[issuerId] or 'Unknown',
            billCount = tonumber(row.bill_count) or 0,
            billSum = tonumber(row.bill_sum) or 0,
        }
    end

    return { success = true, data = out }
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

function BillingService.RevertBillToOutstanding(billId)
    if not billId then return false end
    local changed = update([[
        UPDATE bs_billing_invoices
        SET status = 'outstanding', paid_at = NULL, paid_by_id = NULL, payment_source = NULL
        WHERE id = ? AND status = 'paid'
    ]], { billId })
    return changed and changed > 0
end

function BillingService.PayBillBySource(source, billId)
    billId = tonumber(billId)
    if not billId then
        return { success = false, error = 'invalid bill id' }
    end

    if not tryAcquirePayLock(billId) then
        return { success = false, error = 'payment already in progress' }
    end

    local function finish(result)
        releasePayLock(billId)
        return result
    end

    local payer = BillingFramework.GetPlayer(source)
    if not payer then
        return finish({ success = false, error = 'payer not found' })
    end

    local payerIdentifier = BillingFramework.GetIdentifier(payer)
    if not payerIdentifier then
        return finish({ success = false, error = 'payer identifier missing' })
    end

    local billResult = BillingService.GetBillById(billId)
    if not billResult.success then
        return finish(billResult)
    end
    local bill = billResult.data

    if bill.status ~= 'outstanding' then
        return finish({ success = false, error = 'bill is not outstanding' })
    end
    if not Config.AllowThirdPartyPayments and bill.recipient_id ~= payerIdentifier then
        return finish({ success = false, error = 'bill does not belong to player' })
    end

    local account = Config.Account or 'bank'
    local balance = BillingFramework.GetMoney(payer, account)
    if balance < bill.amount then
        return finish({ success = false, error = 'insufficient funds' })
    end

    -- Atomically claim the bill before moving money (prevents double-pay / race conditions).
    local claimed = BillingService.MarkBillPaid(bill.id, payerIdentifier, account)
    if not claimed.success then
        return finish(claimed)
    end
    bill = claimed.data

    local removed = BillingFramework.RemoveMoney(payer, account, bill.amount, 'bs_billing:pay_bill')
    if not removed then
        BillingService.RevertBillToOutstanding(bill.id)
        return finish({ success = false, error = 'failed to remove bank money' })
    end

    if bill.issuer_type == 'business' then
        if not bill.issuer_job or bill.issuer_job == '' then
            rollbackFailedPayment(payer, bill.id, bill.amount, nil, nil)
            return finish({ success = false, error = 'bill missing business account' })
        end

        local splitOk, splitErr, ledger = payBusinessBillSplits(bill, bill.amount)
        if not splitOk then
            rollbackFailedPayment(payer, bill.id, bill.amount, ledger, nil)
            return finish({ success = false, error = splitErr or 'failed to deposit business payout' })
        end
    elseif bill.issuer_id and bill.issuer_id ~= '' then
        local issuerSource = BillingFramework.GetSourceByIdentifier(bill.issuer_id)
        if issuerSource then
            if not BillingFramework.AddMoney(issuerSource, account, bill.amount, 'bs_billing:issuer_payout') then
                rollbackFailedPayment(payer, bill.id, bill.amount, nil, {
                    issuerId = bill.issuer_id,
                    amount = bill.amount,
                })
                return finish({ success = false, error = 'failed to pay issuer' })
            end
        end
    end

    return finish(BillingService.GetBillById(bill.id))
end
