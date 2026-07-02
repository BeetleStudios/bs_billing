import {
  Box,
  Button,
  Group,
  Loader,
  ScrollArea,
  SegmentedControl,
  Stack,
  Text,
} from "@mantine/core";
import { useCallback, useEffect, useState } from "react";
import { fetchNui, isEnvBrowser } from "../../hooks/useNui";
import global from "../../global.module.css";
import classes from "../appStyle.module.css";
import { BillTrendChart } from "./BillTrendChart";
import type { ApiResult, Bill, LeaderboardRow, TrendBucket, TrendPeriod } from "./types";

type LangMap = Record<string, string>;

type Props = {
  lang: LangMap;
  notify: (title: string, description: string, type?: "success" | "error" | "inform") => void;
};

const MOCK_BUCKETS: TrendBucket[] = [
  { label: "Mon", paidCount: 2, paidSum: 400, outstandingCount: 1, outstandingSum: 150 },
  { label: "Tue", paidCount: 1, paidSum: 200, outstandingCount: 3, outstandingSum: 450 },
  { label: "Wed", paidCount: 3, paidSum: 600, outstandingCount: 2, outstandingSum: 300 },
  { label: "Thu", paidCount: 0, paidSum: 0, outstandingCount: 4, outstandingSum: 800 },
  { label: "Fri", paidCount: 2, paidSum: 350, outstandingCount: 1, outstandingSum: 100 },
  { label: "Sat", paidCount: 1, paidSum: 120, outstandingCount: 0, outstandingSum: 0 },
  { label: "Sun", paidCount: 2, paidSum: 280, outstandingCount: 2, outstandingSum: 220 },
];

const MOCK_LEADERBOARD: LeaderboardRow[] = [
  { issuerId: "a", issuerName: "Officer Smith", billCount: 12, billSum: 4200 },
  { issuerId: "b", issuerName: "Officer Jones", billCount: 8, billSum: 3100 },
];

export function BusinessManagePanel({ lang, notify }: Props) {
  const [section, setSection] = useState<"outstanding" | "analytics" | "leaderboard">("outstanding");
  const [busyId, setBusyId] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);

  const [businessOutstanding, setBusinessOutstanding] = useState<Bill[]>([]);
  const [trendPeriod, setTrendPeriod] = useState<TrendPeriod>("day");
  const [chartMode, setChartMode] = useState<"count" | "sum">("count");
  const [trendBuckets, setTrendBuckets] = useState<TrendBucket[]>([]);
  const [leaderboard, setLeaderboard] = useState<LeaderboardRow[]>([]);

  const loadOutstanding = useCallback(async () => {
    if (isEnvBrowser()) {
      setBusinessOutstanding([
        {
          id: 2001,
          amount: 250,
          reason: "Speeding",
          status: "outstanding",
          recipient_name_snapshot: "John Doe",
          issuer_name_snapshot: "LSPD",
          created_at: "01/02/2026",
        },
      ]);
      return;
    }
    const r = (await fetchNui<ApiResult<Bill[]>>("getBusinessOutstanding")) as ApiResult<Bill[]>;
    setBusinessOutstanding(r?.success && r.data ? r.data : []);
  }, []);

  const loadTrend = useCallback(async () => {
    if (isEnvBrowser()) {
      setTrendBuckets(MOCK_BUCKETS);
      return;
    }
    const r = (await fetchNui<ApiResult<{ buckets: TrendBucket[] }>>("getBusinessBillTrend", {
      period: trendPeriod,
    })) as ApiResult<{ buckets: TrendBucket[] }>;
    setTrendBuckets(r?.success && r.data?.buckets ? r.data.buckets : []);
  }, [trendPeriod]);

  const loadLeaderboard = useCallback(async () => {
    if (isEnvBrowser()) {
      setLeaderboard(MOCK_LEADERBOARD);
      return;
    }
    const r = (await fetchNui<ApiResult<LeaderboardRow[]>>("getBusinessIssuerLeaderboard")) as ApiResult<
      LeaderboardRow[]
    >;
    setLeaderboard(r?.success && r.data ? r.data : []);
  }, []);

  const refreshAll = useCallback(async () => {
    setLoading(true);
    await Promise.all([loadOutstanding(), loadTrend(), loadLeaderboard()]);
    setLoading(false);
  }, [loadOutstanding, loadTrend, loadLeaderboard]);

  useEffect(() => {
    refreshAll();
  }, [refreshAll]);

  useEffect(() => {
    if (section === "analytics") loadTrend();
  }, [section, trendPeriod, loadTrend]);

  const cancelBill = async (bill: Bill) => {
    setBusyId(bill.id);
    const r = (await fetchNui<ApiResult<Bill>>("cancelBill", { billId: bill.id })) as ApiResult<Bill>;
    setBusyId(null);
    if (r?.success) {
      notify(lang.app_title || "Billing", lang.notify_cancelled || "Cancelled", "success");
      await loadOutstanding();
      await loadTrend();
    } else {
      notify(lang.app_title || "Billing", r?.error || "Cancel failed", "error");
    }
  };

  const remindBill = async (bill: Bill) => {
    setBusyId(bill.id);
    const r = (await fetchNui<ApiResult<{ reminded: boolean }>>("remindBill", {
      billId: bill.id,
    })) as ApiResult<{ reminded: boolean }>;
    setBusyId(null);
    if (r?.success) {
      notify(lang.app_title || "Billing", lang.notify_reminder_sent || "Reminder sent.", "success");
    } else {
      notify(lang.app_title || "Billing", r?.error || lang.notify_reminder_failed || "Reminder failed", "error");
    }
  };

  if (loading) {
    return (
      <Group justify="center" py="xl">
        <Loader color="var(--color-main)" size="sm" />
      </Group>
    );
  }

  return (
    <Stack gap="xs" h="100%">
      <SegmentedControl
        fullWidth
        size="xs"
        value={section}
        onChange={(v) => setSection(v as typeof section)}
        data={[
          { value: "outstanding", label: lang.biz_section_outstanding || "Outstanding" },
          { value: "analytics", label: lang.biz_section_analytics || "Analytics" },
          { value: "leaderboard", label: lang.biz_section_leaderboard || "Top staff" },
        ]}
      />

      {section === "outstanding" && (
        <ScrollArea className={classes.scrollArea} type="auto" scrollbarSize={6}>
          <Stack gap={0}>
            {businessOutstanding.length === 0 ? (
              <Text c="dimmed" fz="xs">
                {lang.biz_empty_outstanding || "No outstanding business bills."}
              </Text>
            ) : (
              businessOutstanding.map((b) => (
                <Group
                  key={b.id}
                  className={classes.billRow}
                  justify="space-between"
                  wrap="nowrap"
                  align="flex-start"
                >
                  <Box style={{ minWidth: 0 }}>
                    <Text fw={600} c="white" fz="sm" truncate>
                      #{b.id} — ${b.amount}
                    </Text>
                    <Text fz="xs" c="gray.3" lineClamp={2}>
                      {b.reason}
                    </Text>
                    <Text className={classes.meta}>
                      {lang.to || "To"}: {b.recipient_name_snapshot || "—"} · {b.created_at || ""}
                    </Text>
                  </Box>
                  <Stack gap={4} w={76}>
                    <Button
                      size="xs"
                      className={global.button}
                      onClick={() => remindBill(b)}
                      disabled={busyId === b.id}
                      p={4}
                    >
                      {lang.remind || "Remind"}
                    </Button>
                    <Button
                      size="xs"
                      variant="outline"
                      color="gray"
                      onClick={() => cancelBill(b)}
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

      {section === "analytics" && (
        <Stack gap="xs">
          <SegmentedControl
            fullWidth
            size="xs"
            value={trendPeriod}
            onChange={(v) => setTrendPeriod(v as TrendPeriod)}
            data={[
              { value: "day", label: lang.biz_period_day || "7 days" },
              { value: "week", label: lang.biz_period_week || "4 weeks" },
              { value: "month", label: lang.biz_period_month || "6 months" },
            ]}
          />
          <SegmentedControl
            fullWidth
            size="xs"
            value={chartMode}
            onChange={(v) => setChartMode(v as "count" | "sum")}
            data={[
              { value: "count", label: lang.biz_chart_count || "Count" },
              { value: "sum", label: lang.biz_chart_sum || "Amount" },
            ]}
          />
          <BillTrendChart
            buckets={trendBuckets}
            countMode={chartMode === "count"}
            paidLabel={lang.biz_chart_paid || "Paid"}
            outstandingLabel={lang.biz_chart_outstanding || "Outstanding"}
            tapHint={lang.biz_chart_tap_hint || "Tap a point for counts and amounts"}
          />
        </Stack>
      )}

      {section === "leaderboard" && (
        <ScrollArea className={classes.scrollArea} type="auto" scrollbarSize={6}>
          <Stack gap={0}>
            {leaderboard.length === 0 ? (
              <Text c="dimmed" fz="xs">
                {lang.biz_empty_leaderboard || "No issued bills from current staff."}
              </Text>
            ) : (
              leaderboard.map((row, idx) => (
                <Group key={row.issuerId} className={classes.billRow} justify="space-between" wrap="nowrap">
                  <Box>
                    <Text fw={600} c="white" fz="sm">
                      #{idx + 1} {row.issuerName}
                    </Text>
                    <Text className={classes.meta}>
                      {(lang.biz_leaderboard_meta || "%count bills · $%sum")
                        .replace("%count", String(row.billCount))
                        .replace("%sum", String(row.billSum))}
                    </Text>
                  </Box>
                </Group>
              ))
            )}
          </Stack>
        </ScrollArea>
      )}
    </Stack>
  );
}
