import { Box, Group, Text } from "@mantine/core";
import { useRecoilValue } from "recoil";
import { Lang } from "../reducers/atoms";
import shell from "./nuiShell.module.css";

export type IncomingBillPayload = {
  amount?: number;
  issuerName?: string;
  reason?: string;
  billId?: number;
  openKey?: string;
  dismissKey?: string | false;
  isReminder?: boolean;
};

type Props = {
  data: IncomingBillPayload;
  onDismiss: () => void;
};

export function IncomingBillAlert({ data, onDismiss }: Props) {
  const lang = useRecoilValue(Lang);
  const amount = data.amount ?? 0;
  const issuer = data.issuerName || lang.app_title || "Billing";
  const openKey = data.openKey || "E";
  const dismissKey = data.dismissKey;
  const pressOpen =
    (lang.incoming_bill_press_key || "Press [%s] to open").replace("%s", openKey);
  const pressDismiss =
    dismissKey !== false && dismissKey
      ? (lang.incoming_bill_dismiss_key || "[%s] to dismiss").replace(
          "%s",
          String(dismissKey)
        )
      : null;

  return (
    <Box className={shell.alertWrap}>
      <Box className={shell.alertCard}>
        <span
          className={shell.closeBtn}
          role="button"
          tabIndex={0}
          onClick={onDismiss}
          onKeyDown={(e) => {
            if (e.key === "Enter" || e.key === " ") {
              e.preventDefault();
              onDismiss();
            }
          }}
          aria-label="Dismiss"
        >
          ×
        </span>
        <Group gap={8} wrap="nowrap" align="flex-start" pr={16}>
          <Text ff="Bebas Neue" fz="1.1rem" c="var(--color-main)" lts={1}>
            {data.isReminder
              ? lang.incoming_bill_reminder_title || "Bill reminder"
              : lang.incoming_bill_title || "New bill"}
          </Text>
        </Group>
        <Text fz="sm" c="white" fw={600} mt={4}>
          ${amount}
        </Text>
        <Text fz="xs" c="dimmed" mt={4} lineClamp={2}>
          {(lang.incoming_bill_from || "From: %s").replace("%s", issuer)}
        </Text>
        {data.reason ? (
          <Text fz="xs" c="gray.4" mt={2} lineClamp={1}>
            {data.reason}
          </Text>
        ) : null}
        <Text fz={10} c="var(--color-main)" mt={8} tt="uppercase" lts={1}>
          {pressOpen}
        </Text>
        {pressDismiss ? (
          <Text fz={10} c="dimmed" mt={4} tt="uppercase" lts={0.5}>
            {pressDismiss}
          </Text>
        ) : null}
      </Box>
    </Box>
  );
}
