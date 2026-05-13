Config = {}

Config.Framework = 'qbx' -- 'qb', 'qbx', 'esx'
Config.Banking = 'renewed' -- 'renewed', 'qb', 'okok', 'fd', 'tgiann', 'esx_addonaccount'

Config.Command = 'billing'
Config.EnableBillingCommand = true
Config.Account = 'bank'

Config.MinAmount = 1
Config.MaxAmount = 1000000
Config.MaxReasonLength = 120
Config.HistoryPageSize = 25

Config.NearbyBillTargetRadius = 5.0 -- meters
Config.NearbyBillTargetMax = 5 -- max entries in the list (closest first)

Config.AllowPersonalBillByAnyone = true
Config.AllowThirdPartyPayments = true

-- When true (default), new bills also trigger an lb-phone notification (standard notification sound) if lb-phone is started on the client.
Config.LbPhoneBillNotify = false
-- `app` field on lb-phone notifications; use your custom app identifier so tapping opens the Billing app when installed.
Config.LbPhoneBillAppIdentifier = 'bs_billing_phone'

-- Map job name => minimum job grade required to create business bills.
Config.BusinessBillingJobs = {
    police = 0,
    ambulance = 0,
    mechanic = 0,
    ottos = 0
}

-- Map job name => commission rate (0–1) for business bills when paid.
-- Example: police = 0.1 means 10% to the issuing player (bank) and 90% to the society account.
-- Jobs not listed (or 0) send 100% to society. If the issuer is offline, commission goes to society.
Config.BusinessCommissionPercent = {
    police = 0.1,
    ambulance = 0.1,
    mechanic = 0.1,
    ottos = 0.1
}
