import {
  Box,
  Text,
  Group,
  Button,
  ScrollArea,
  Stack,
  Badge,
  Loader,
  Select,
  TextInput,
  NumberInput,
  Modal,
  SegmentedControl,
} from "@mantine/core";
import { useCallback, useEffect, useMemo, useState } from "react";
import { fetchNui, isEnvBrowser } from "../hooks/useNui";
import { useRecoilValue } from "recoil";
import { Lang } from "../reducers/atoms";
import { BusinessManagePanel } from "./business/BusinessManagePanel";
import classes from "./appStyle.module.css";
import global from "../global.module.css";

type ApiResult<T> = { success: boolean; data?: T; error?: string };

type Bill = {
  id: number;
  amount: number;
  reason: string;
  status: string;
  issuer_name_snapshot?: string;
  issuer_type?: string;
  issuer_job?: string;
  created_at?: string;
  recipient_name_snapshot?: string;
};

type TargetOption = { value: string; label: string };

type BillingContext = {
  currentJob?: string;
  currentJobLabel?: string;
  canCreatePersonal?: boolean;
  canCreateBusinessCurrentJob?: boolean;
  canCreateAny?: boolean;
  allowPersonalBilling?: boolean;
  canManageBusiness?: boolean;
};

const MOCK_BILLS: Bill[] = [
  {
    id: 1001,
    amount: 500,
    reason: "Parking",
    status: "outstanding",
    issuer_name_snapshot: "LSPD",
    issuer_type: "business",
    issuer_job: "police",
    created_at: "01/01/2026 12:00 PM",
    recipient_name_snapshot: "Jane Doe",
  },
];

async function nuiNotify(
  title: string,
  description: string,
  type: "success" | "error" | "inform" = "inform"
) {
  if (isEnvBrowser()) {
    console.log(title, description);
    return;
  }
  await fetchNui("uiNotify", { title, description, type });
}

type MainAppProps = {
  initialTab?: "outstanding" | "history" | "create" | "manage";
  onClose?: () => void;
};

export const MainApp = ({ initialTab = "outstanding", onClose }: MainAppProps) => {
  const lang = useRecoilValue(Lang);
  const [tab, setTab] = useState<"outstanding" | "history" | "create" | "manage">(initialTab);
  const [loading, setLoading] = useState(true);
  const [outstanding, setOutstanding] = useState<Bill[]>([]);
  const [history, setHistory] = useState<Bill[]>([]);
  const [historyKind, setHistoryKind] = useState<"received" | "issued">("received");
  const [busyId, setBusyId] = useState<number | null>(null);

  const [payBill, setPayBill] = useState<Bill | null>(null);

  const [ctx, setCtx] = useState<BillingContext | null>(null);
  const [targetOptions, setTargetOptions] = useState<TargetOption[]>([]);
  const [manualToken, setManualToken] = useState("__bs_billing_manual_target__");
  const [targetSelect, setTargetSelect] = useState<string | null>(null);
  const [manualServerId, setManualServerId] = useState<string>("");
  const [amount, setAmount] = useState<number | string>(100);
  const [reason, setReason] = useState<string>("");
  const [issuerType, setIssuerType] = useState<string>("person");
  const [createBusy, setCreateBusy] = useState(false);
  const [createMetaReady, setCreateMetaReady] = useState(false);

  const loadOutstanding = useCallback(async () => {
    if (isEnvBrowser()) {
      setOutstanding(MOCK_BILLS);
      return;
    }
    const r = (await fetchNui<ApiResult<Bill[]>>("getOutstanding")) as ApiResult<Bill[]>;
    if (r?.success && r.data) setOutstanding(r.data);
    else setOutstanding([]);
  }, []);

  const loadHistoryRows = useCallback(async () => {
    if (isEnvBrowser()) {
      setHistory(MOCK_BILLS);
      return;
    }
    const action = historyKind === "issued" ? "getIssuedHistory" : "getHistory";
    const r = (await fetchNui<ApiResult<Bill[]>>(action, {
      limit: 50,
      offset: 0,
    })) as ApiResult<Bill[]>;
    if (r?.success && r.data) setHistory(r.data);
    else setHistory([]);
  }, [historyKind]);

  const loadContext = useCallback(async () => {
    if (isEnvBrowser()) {
      setCtx({
        currentJob: "police",
        currentJobLabel: "LSPD",
        canCreatePersonal: true,
        canCreateBusinessCurrentJob: true,
        canManageBusiness: true,
      });
      return;
    }
    const c = (await fetchNui<ApiResult<BillingContext>>("getContext")) as ApiResult<BillingContext>;
    if (c?.success && c.data) setCtx(c.data);
    else setCtx({});
  }, []);

  const refresh = useCallback(async () => {
    setLoading(true);
    await loadContext();
    await loadOutstanding();
    await loadHistoryRows();
    setLoading(false);
  }, [loadContext, loadOutstanding, loadHistoryRows]);

  const loadCreateMeta = useCallback(async () => {
    setCreateMetaReady(false);
    if (isEnvBrowser()) {
      setCtx({ currentJob: "police", currentJobLabel: "LSPD", canCreatePersonal: true, canCreateBusinessCurrentJob: true });
      const m = "__bs_billing_manual_target__";
      setManualToken(m);
      setTargetOptions([
        { value: "2", label: "Server Id #2 - Test" },
        { value: m, label: "Manual server ID…" },
      ]);
      setTargetSelect("2");
      setCreateMetaReady(true);
      return;
    }
    const [c, t] = await Promise.all([
      fetchNui<ApiResult<BillingContext>>("getContext"),
      fetchNui<{ success: boolean; options?: TargetOption[]; manualValue?: string }>("getCreateTargets"),
    ]);
    if (c?.success && c.data) {
      setCtx(c.data);
      const personal = c.data.canCreatePersonal !== false;
      const business = c.data.canCreateBusinessCurrentJob === true;
      if (!personal && business) {
        setIssuerType("business");
      } else if (personal && !business) {
        setIssuerType("person");
      }
    } else {
      setCtx({});
    }
    if (t?.success && t.options) {
      setTargetOptions(t.options);
      if (t.manualValue) setManualToken(t.manualValue);
      const first = t.options[0]?.value ?? null;
      setTargetSelect(first);
    } else {
      setTargetOptions([]);
      setTargetSelect(null);
    }
    setCreateMetaReady(true);
  }, []);

  useEffect(() => {
    document.documentElement.style.setProperty("--color-main", "#c0eb75");
    document.documentElement.style.setProperty("--color-text", "#0b0b0f");
  }, []);

  useEffect(() => {
    setTab(initialTab);
  }, [initialTab]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  useEffect(() => {
    if (tab === "outstanding") loadOutstanding();
    if (tab === "create") loadCreateMeta();
  }, [tab, loadOutstanding, loadCreateMeta]);

  useEffect(() => {
    if (tab === "history") loadHistoryRows();
  }, [tab, historyKind, loadHistoryRows]);

  const runPay = async (bill: Bill) => {
    setBusyId(bill.id);
    const r = (await fetchNui<ApiResult<Bill>>("payBill", { billId: bill.id })) as ApiResult<Bill>;
    setBusyId(null);
    setPayBill(null);
    if (r?.success) {
      nuiNotify(lang.app_title || "Billing", lang.notify_paid || "Paid", "success");
      await loadOutstanding();
      await loadHistoryRows();
    } else {
      nuiNotify(
        lang.app_title || "Billing",
        r?.error || lang.notify_pay_failed || "Pay failed",
        "error"
      );
    }
  };

  const cancel = async (bill: Bill) => {
    setBusyId(bill.id);
    const r = (await fetchNui<ApiResult<Bill>>("cancelBill", { billId: bill.id })) as ApiResult<Bill>;
    setBusyId(null);
    if (r?.success) {
      nuiNotify(lang.app_title || "Billing", lang.notify_cancelled || "Cancelled", "success");
      await loadOutstanding();
      await loadHistoryRows();
    } else {
      nuiNotify(lang.app_title || "Billing", r?.error || "Cancel failed", "error");
    }
  };

  const submitCreate = async () => {
    const manualPick = targetSelect === manualToken;
    let targetSource: number;
    if (manualPick) {
      targetSource = parseInt(manualServerId, 10);
      if (!targetSource || targetSource < 1) {
        await nuiNotify(lang.app_title || "Billing", lang.create_target_manual_required || "Enter server ID");
        return;
      }
    } else {
      targetSource = parseInt(targetSelect || "", 10);
      if (!targetSource || targetSource < 1) {
        await nuiNotify(lang.app_title || "Billing", lang.create_target_invalid || "Invalid target");
        return;
      }
    }

    const amountNum =
      typeof amount === "number" ? amount : parseInt(String(amount), 10);
    if (!amountNum || amountNum < 1) {
      await nuiNotify(lang.app_title || "Billing", lang.invalid_amount || "Invalid amount");
      return;
    }
    const reasonTrim = reason.trim();
    if (!reasonTrim) {
      await nuiNotify(lang.app_title || "Billing", "Reason required");
      return;
    }

    if (issuerType === "person" && !canCreatePersonal) {
      await nuiNotify(lang.app_title || "Billing", lang.no_personal || "Personal billing disabled.");
      return;
    }

    if (issuerType === "business") {
      if (!ctx?.currentJob || String(ctx.currentJob).trim() === "") {
        await nuiNotify(
          lang.app_title || "Billing",
          lang.create_business_need_job || "You need a job on your character to create a business bill."
        );
        return;
      }
      if (!canCreateBusiness) {
        await nuiNotify(lang.app_title || "Billing", lang.no_business || "Business billing not allowed.");
        return;
      }
    }

    const job = issuerType === "business" ? (ctx?.currentJob || "") : "";

    setCreateBusy(true);
    const r = (await fetchNui<ApiResult<Bill>>("createBill", {
      payload: {
        targetSource,
        amount: amountNum,
        reason: reasonTrim,
        issuerType,
        issuerJob: job,
      },
    })) as ApiResult<Bill>;
    setCreateBusy(false);

    if (r?.success) {
      nuiNotify(lang.app_title || "Billing", lang.notify_created || "Created", "success");
      setReason("");
      setAmount(100);
      await loadOutstanding();
      await loadHistoryRows();
      setTab("outstanding");
    } else {
      nuiNotify(lang.app_title || "Billing", r?.error || "Create failed", "error");
    }
  };

  const statusColor = (s: string) => {
    if (s === "paid") return "green";
    if (s === "cancelled") return "gray";
    return "yellow";
  };

  const localizedStatus = (s: string) => {
    if (s === "paid") return lang.status_paid || s;
    if (s === "cancelled") return lang.status_cancelled || s;
    if (s === "outstanding") return lang.status_outstanding || s;
    return s;
  };

  const canCreatePersonal = ctx?.canCreatePersonal !== false;
  const canCreateBusiness = ctx?.canCreateBusinessCurrentJob === true;
  const canCreateAny = ctx?.canCreateAny ?? (canCreatePersonal || canCreateBusiness);
  const canManageBusiness = ctx?.canManageBusiness === true;

  const billTypeOptions = useMemo(() => {
    const opts: { value: string; label: string }[] = [];
    if (canCreatePersonal) {
      opts.push({ value: "person", label: lang.create_type_personal || "Personal" });
    }
    if (canCreateBusiness) {
      opts.push({ value: "business", label: lang.create_type_business || "Business" });
    }
    return opts;
  }, [canCreatePersonal, canCreateBusiness, lang.create_type_personal, lang.create_type_business]);

  useEffect(() => {
    if (!createMetaReady || billTypeOptions.length === 0) return;
    const allowed = billTypeOptions.some((o) => o.value === issuerType);
    if (!allowed) {
      setIssuerType(billTypeOptions[0].value);
    }
  }, [createMetaReady, billTypeOptions, issuerType]);

  const TabBtn = ({
    id,
    label,
  }: {
    id: "outstanding" | "history" | "create" | "manage";
    label: string;
  }) => (
    <Box
      className={`${global.tab} ${tab === id ? global.tabActive : ""}`}
      onClick={() => setTab(id)}
    >
      {label}
    </Box>
  );

  return (
    <Box className={classes.app}>
      <Box className={classes.container}>
        <Stack gap={6} className={`${global.header} ${classes.headerRow}`} p="xs">
          <Box className={classes.headerTop}>
            <Box style={{ minWidth: 0 }}>
              <Text ff="Bebas Neue" fz="1.2rem" lts={2} c="white" lh={1.1}>
                {lang.app_title || "Billing"}
              </Text>
              <Text fz={10} c="dimmed" lineClamp={2}>
                {lang.app_subtitle || "Invoices & fines"}
              </Text>
            </Box>
            {onClose ? (
              <Box
                component="button"
                type="button"
                onClick={onClose}
                style={{
                  background: "transparent",
                  border: "none",
                  color: "rgba(255,255,255,0.6)",
                  cursor: "pointer",
                  fontSize: 18,
                  lineHeight: 1,
                  padding: "4px 6px",
                  flexShrink: 0,
                }}
                aria-label="Close"
              >
                ×
              </Box>
            ) : null}
          </Box>
          <Group gap={4} wrap="wrap" className={classes.tabNav}>
            <TabBtn id="outstanding" label={lang.tab_outstanding || "Due"} />
            <TabBtn id="history" label={lang.tab_history || "History"} />
            {canManageBusiness ? (
              <TabBtn id="manage" label={lang.tab_manage || "Manage"} />
            ) : null}
            <TabBtn id="create" label={lang.tab_create || "Create"} />
          </Group>
        </Stack>

        <Box className={classes.main}>
          {loading && tab !== "create" ? (
            <Group justify="center" py="xl">
              <Loader color="var(--color-main)" size="sm" />
            </Group>
          ) : (
            <Box
              className={`${global.content} ${classes.panel}`}
              p="sm"
              style={{ borderRadius: 8 }}
            >
              {tab === "outstanding" && (
                <ScrollArea className={classes.scrollArea} type="auto" scrollbarSize={6}>
                  <Stack gap={0}>
                    {outstanding.length === 0 ? (
                      <Text c="dimmed" fz="xs">
                        {lang.empty_outstanding || "No outstanding bills."}
                      </Text>
                    ) : (
                      outstanding.map((b) => (
                        <Group
                          key={b.id}
                          className={classes.billRow}
                          justify="space-between"
                          wrap="nowrap"
                          align="flex-start"
                        >
                          <Box style={{ minWidth: 0 }}>
                            <Group gap={6}>
                              <Text fw={600} c="white" fz="sm" truncate>
                                #{b.id} — ${b.amount}
                              </Text>
                              <Badge size="xs" color={statusColor(b.status)}>
                                {localizedStatus(b.status)}
                              </Badge>
                            </Group>
                            <Text fz="xs" c="gray.3" lineClamp={2}>
                              {b.reason}
                            </Text>
                            <Text className={classes.meta}>
                              {lang.from || "From"}: {b.issuer_name_snapshot || "—"} · {b.created_at || ""}
                            </Text>
                          </Box>
                          <Stack gap={4} w={72}>
                            <Button
                              size="xs"
                              className={global.button}
                              onClick={() => setPayBill(b)}
                              disabled={busyId === b.id}
                              p={4}
                            >
                              {lang.pay || "Pay"}
                            </Button>
                            <Button
                              size="xs"
                              variant="outline"
                              color="gray"
                              onClick={() => cancel(b)}
                              disabled={busyId === b.id}
                              p={4}
                            >
                              {lang.cancel || "Cancel"}
                            </Button>
                          </Stack>
                        </Group>
                      ))
                    )}
                  </Stack>
                </ScrollArea>
              )}

              {tab === "history" && (
                <>
                  <SegmentedControl
                    fullWidth
                    size="xs"
                    mb="xs"
                    value={historyKind}
                    onChange={(v) => setHistoryKind(v as "received" | "issued")}
                    data={[
                      { value: "received", label: lang.history_kind_received || "Received" },
                      { value: "issued", label: lang.history_kind_issued || "Issued" },
                    ]}
                  />
                  <ScrollArea className={classes.scrollArea} type="auto" scrollbarSize={6}>
                    <Stack gap={0}>
                      {history.length === 0 ? (
                        <Text c="dimmed" fz="xs">
                          {lang.empty_history || "No history."}
                        </Text>
                      ) : (
                        history.map((b) => (
                          <Box key={b.id} className={classes.billRow}>
                            <Group gap={6}>
                              <Text fw={600} c="white" fz="sm">
                                #{b.id} — ${b.amount}
                              </Text>
                              <Badge size="xs" color={statusColor(b.status)}>
                                {localizedStatus(b.status)}
                              </Badge>
                            </Group>
                            <Text fz="xs" c="gray.3">
                              {b.reason}
                            </Text>
                            <Text className={classes.meta}>
                              {historyKind === "issued"
                                ? `${lang.to || "To"}: ${b.recipient_name_snapshot || "—"}`
                                : `${lang.from || "From"}: ${b.issuer_name_snapshot || "—"}`}{" "}
                              · {b.created_at || ""}
                            </Text>
                          </Box>
                        ))
                      )}
                    </Stack>
                  </ScrollArea>
                </>
              )}

              {tab === "manage" && canManageBusiness && (
                <BusinessManagePanel
                  lang={lang}
                  notify={(title, description, type) => nuiNotify(title, description, type)}
                />
              )}

              {tab === "create" && (
                <ScrollArea className={classes.scrollArea} type="auto" scrollbarSize={6}>
                  {!createMetaReady ? (
                    <Group justify="center" py="md">
                      <Loader color="var(--color-main)" size="sm" />
                    </Group>
                  ) : ctx && !canCreateAny ? (
                    <Text c="orange" fz="xs">
                      {lang.no_create_billing ||
                        "You cannot create bills. Personal billing is disabled and your job cannot issue business bills."}
                    </Text>
                  ) : ctx && issuerType === "business" && (!ctx.currentJob || String(ctx.currentJob).trim() === "") ? (
                    <Text c="orange" fz="xs">
                      {lang.create_business_need_job ||
                        "You need a framework job on your character to create a business bill."}
                    </Text>
                  ) : ctx && issuerType === "business" && !canCreateBusiness ? (
                    <Text c="orange" fz="xs">
                      {lang.no_business || "You cannot create business bills for your current job."}
                    </Text>
                  ) : (
                    <Stack gap="sm">
                      <Select
                        label={lang.create_target || "Target"}
                        data={targetOptions}
                        value={targetSelect}
                        onChange={setTargetSelect}
                        size="xs"
                        comboboxProps={{ withinPortal: true }}
                      />
                      {targetSelect === manualToken && (
                        <TextInput
                          label={lang.create_target_manual_id || "Manual server ID"}
                          description={lang.create_target_manual_hint}
                          value={manualServerId}
                          onChange={(e) => setManualServerId(e.currentTarget.value)}
                          size="xs"
                        />
                      )}
                      <NumberInput
                        label={lang.create_amount || "Amount"}
                        min={1}
                        value={amount}
                        onChange={setAmount}
                        size="xs"
                      />
                      <TextInput
                        label={lang.create_reason || "Reason"}
                        value={reason}
                        onChange={(e) => setReason(e.currentTarget.value)}
                        maxLength={120}
                        size="xs"
                      />
                      {billTypeOptions.length > 1 && (
                        <Select
                          label={lang.create_type || "Type"}
                          data={billTypeOptions}
                          value={issuerType}
                          onChange={(v) => setIssuerType(v || billTypeOptions[0]?.value || "person")}
                          size="xs"
                        />
                      )}
                      <Button
                        className={global.button}
                        onClick={submitCreate}
                        loading={createBusy}
                        size="sm"
                      >
                        {lang.submit_create || "Create bill"}
                      </Button>
                    </Stack>
                  )}
                </ScrollArea>
              )}
            </Box>
          )}
        </Box>
      </Box>

      <Modal
        opened={payBill !== null}
        onClose={() => setPayBill(null)}
        title={lang.confirm_pay_title || "Pay bill"}
        size="sm"
        centered
      >
        {payBill && (
          <Stack gap="md">
            <Text fz="sm">
              {(lang.confirm_pay_desc || "Pay $%s for: %s")
                .replace("%s", String(payBill.amount))
                .replace("%s", String(payBill.reason))}
            </Text>
            <Group justify="flex-end">
              <Button variant="subtle" onClick={() => setPayBill(null)}>
                {lang.confirm_no || "Back"}
              </Button>
              <Button className={global.button} onClick={() => runPay(payBill)}>
                {lang.confirm_yes || "Pay"}
              </Button>
            </Group>
          </Stack>
        )}
      </Modal>
    </Box>
  );
};
