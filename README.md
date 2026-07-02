# bs_billing - FiveM Billing/Invoice/Fine Script

A simple cross-framework billing resource for FiveM. Players and jobs can issue **personal** or **business** bills; recipients see **outstanding** balances until they pay from their **bank account**. Business payments route to your society account via your banking script. Default UI is a **React + Mantine** NUI (phone-style panel on the right); set `Config.UseBillingNui = false` for ox_lib menus only.

**[Preview](https://youtu.be/2rpbGGr4uh4)**

## Features

- **Outstanding bills** — Persist until paid or cancelled
- **History** — Past bills (paid / cancelled) with pagination support via exports
- **Management** — Managers and Owners can access ALL business bills, cancel any of them and send reminders
- **Analytics and Leaderboard** — Managers and Owners can view oustanding and paid bills by 7 day, 4 week or 6 month trend lines AND see a leaderboard of workers based on top bill issuance
- **Personal bills** — Optional payout to the issuer when the bill is paid (if issuer is online)
- **Business bills** — Payment can be split: optional **commission** (per job, 0–1) to the issuing player’s bank (online or offline when the framework supports it), remainder to the **society** account; if commission cannot be credited to the issuer, it falls back to society
- **Framework support** — Qbox, QBCore, or ESX
- **Society banking** — Renewed-Banking, qb-banking, okokBanking, fd_banking, tgiann-bank, esx_addonaccount, wasabi_banking, tgg-banking, p_banking
- **Exports** — Create, query, pay, cancel, and mark bills from other resources
- **Locales** — English, Spanish, Portuguese (`locales/*.json`)

Optional companion: **[bs_billing_phone](https://beetle-studios.tebex.io/package/7445398)** (lb-phone app)

## Dependencies

1. **ox_lib**
2. **oxmysql**
3. One of: **qbx_core**, **qb-core**, or **es_extended** (match `Config.Framework`)

## Installation

1. Place `bs_billing` in your `[standalone]` folder (or your preferred resources path)
2. Add to `server.cfg` **after** `ox_lib` and `oxmysql`, and **before** anything that depends on it, for example:
   - `ensure ox_lib`
   - `ensure oxmysql`
   - `ensure bs_billing`
3. The resource creates the `bs_billing_invoices` table automatically on start (no separate SQL file required)
4. Edit `config.lua` (framework, banking, jobs, limits) — see below
5. Restart the server or `ensure bs_billing`

### NUI build (after editing `ui/src`)

```bash
cd ui
npm install
npm run build
```

Built assets are written to `ui/dist/` (served via `ui_page` in `fxmanifest.lua`).

## Usage

- **In-game UI**: If `Config.UseBillingNui` is enabled (default), `/billing` opens a React + Mantine panel on the right (phone-sized). New bills show an on-screen alert; press `Config.NewBillAlertOpenKey` to open billing. Pay/create/cancel feedback uses ox_lib notifications. Set `Config.UseBillingNui = false` for ox_lib menus only
- **Recipient**: Only the billed player can use **Pay** in the default flow unless third-party payment is enabled in config
- **Integration**: Other resources should use **server exports** to create or manage bills; use the **client export** `OpenMainMenu` to open billing (NUI or ox_lib depending on config)

## Configuration

Edit `config.lua`:

| Option | Description |
|--------|-------------|
| `Config.Framework` | `'qbx'`, `'qb'`, or `'esx'` |
| `Config.Banking` | `'renewed'`, `'qb'`, `'okok'`, `'fd'`, `'tgiann'`, `'esx_addonaccount'`, `'wasabi'`, `'tgg'`,, `'pscripts'`
| `Config.Command` | Chat command name (default: `'billing'`) |
| `Config.EnableBillingCommand` | `true` / `false` — register `/billing` on server and client |
| `Config.Account` | Player account used to pay (default: `'bank'`) |
| `Config.MinAmount` / `Config.MaxAmount` | Bill amount bounds |
| `Config.MaxReasonLength` | Max length for reason text |
| `Config.HistoryPageSize` | Default page size for history queries |
| `Config.UseBillingNui` | `true` = React NUI panel; `false` = ox_lib menus |
| `Config.BillingNuiAlert` | When `UseBillingNui` is true, show incoming-bill alert on the right (no duplicate ox_lib new-bill toast) |
| `Config.NewBillAlertOpenKey` | FiveM key name to open billing from the alert (default `E`) |
| `Config.NewBillAlertDismissKey` | Key to dismiss the alert (default `BACK`); set `false` to disable |
| `Config.AllowPersonalBilling` | If `false`, only **business** bills can be created (for jobs in `BusinessBillingJobs` with sufficient grade). Personal bills are blocked in the menu, phone app, and exports |
| `Config.AllowThirdPartyPayments` | If `false`, only the **recipient** can pay the bill |
| `Config.BusinessBillingJobs` | Table of **job names** (not labels) → minimum **grade** allowed to create **business** bills |
| `Config.BusinessManagerJobs` | Table of **job names** → minimum **grade** for manager tools (all business outstanding, analytics, reminders, cancel any business bill) |
| `Config.BusinessCommissionPercent` | Table of **job names** → commission rate **0–1** on **paid** business bills (e.g. `0.1` = 10% to issuer bank, 90% to society). Omitted jobs = no commission (100% society). If paying the issuer fails, commission goes to society |

## Exports

### Server

Responses use `{ success = true, data = ... }` or `{ success = false, error = '...' }`.

- `exports['bs_billing']:CreateBill(data)` — Full control; `data` includes `recipientId`, `recipientName`, `issuerId`, `issuerName`, `issuerType` (`'person'` \| `'business'`), `issuerJob` (required for business), `amount`, `reason`
- `exports['bs_billing']:CreatePlayerBill(targetSource, amount, reason, options)` — Personal bill; `options` may include `issuerId`, `issuerName`
- `exports['bs_billing']:CreateBusinessBill(targetSource, amount, reason, jobName, options)` — Business bill for society `jobName`; `options` may include `issuerId`, `issuerName`
- `exports['bs_billing']:GetOutstandingBillsBySource(source)`
- `exports['bs_billing']:GetOutstandingBillsByIdentifier(identifier)`
- `exports['bs_billing']:GetBillHistoryBySource(source, limit, offset)`
- `exports['bs_billing']:GetBillHistoryByIdentifier(identifier, limit, offset)`
- `exports['bs_billing']:GetBillById(billId)`
- `exports['bs_billing']:PayBill(source, billId)`
- `exports['bs_billing']:CancelBill(billId, actorSource)`
- `exports['bs_billing']:MarkBillPaid(billId, metadata)` — Admin/integration; `metadata` may include `paidById`, `paymentSource`

### Client

- `exports['bs_billing']:OpenMainMenu()` — Opens the ox_lib billing menu (Outstanding, History, Create), same as the `/billing` command when enabled. Call from client scripts only (for example a radial menu, target, or tablet resource).
