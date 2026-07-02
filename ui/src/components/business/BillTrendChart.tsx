import { Box, Group, Text } from "@mantine/core";
import { useState } from "react";
import type { TrendBucket } from "./types";

type Props = {
  buckets: TrendBucket[];
  paidLabel: string;
  outstandingLabel: string;
  countMode?: boolean;
  tapHint?: string;
};

function formatMoney(n: number) {
  return `$${n.toLocaleString()}`;
}

export function BillTrendChart({
  buckets,
  paidLabel,
  outstandingLabel,
  countMode = true,
  tapHint = "Tap a point for details",
}: Props) {
  const [selected, setSelected] = useState<number | null>(null);

  if (!buckets.length) {
    return (
      <Text c="dimmed" fz="xs">
        No data
      </Text>
    );
  }

  const width = 280;
  const height = 150;
  const padL = 44;
  const padR = 8;
  const padT = 10;
  const padB = 26;
  const innerW = width - padL - padR;
  const innerH = height - padT - padB;

  const valueFor = (b: TrendBucket, field: "paid" | "outstanding") => {
    if (field === "paid") return countMode ? b.paidCount : b.paidSum;
    return countMode ? b.outstandingCount : b.outstandingSum;
  };

  const values = buckets.flatMap((b) => [valueFor(b, "paid"), valueFor(b, "outstanding")]);
  const maxVal = Math.max(1, ...values);

  const xAt = (i: number) => padL + (i / Math.max(buckets.length - 1, 1)) * innerW;
  const yAt = (v: number) => padT + innerH - (v / maxVal) * innerH;

  const formatAxis = (v: number) => {
    if (countMode) return String(Math.round(v));
    if (v >= 1000) return `$${Math.round(v / 1000)}k`;
    return `$${Math.round(v)}`;
  };

  const linePath = (field: "paid" | "outstanding") => {
    const pts = buckets.map((b, i) => {
      const v = valueFor(b, field);
      return `${i === 0 ? "M" : "L"} ${xAt(i).toFixed(1)} ${yAt(v).toFixed(1)}`;
    });
    return pts.join(" ");
  };

  const active = selected !== null ? buckets[selected] : null;

  return (
    <Box>
      <svg width="100%" viewBox={`0 0 ${width} ${height}`} style={{ display: "block" }}>
        {[0, 0.5, 1].map((f) => {
          const y = padT + innerH * (1 - f);
          const val = maxVal * f;
          return (
            <g key={f}>
              <line
                x1={padL}
                y1={y}
                x2={width - padR}
                y2={y}
                stroke="rgba(255,255,255,0.08)"
                strokeWidth={1}
              />
              <text
                x={padL - 4}
                y={y + 3}
                textAnchor="end"
                fill="rgba(180,180,190,0.75)"
                fontSize={8}
              >
                {formatAxis(val)}
              </text>
            </g>
          );
        })}
        <path d={linePath("outstanding")} fill="none" stroke="#f59e0b" strokeWidth={2} />
        <path d={linePath("paid")} fill="none" stroke="#84cc16" strokeWidth={2} />
        {buckets.map((b, i) => {
          const paidY = yAt(valueFor(b, "paid"));
          const outY = yAt(valueFor(b, "outstanding"));
          const isSel = selected === i;
          return (
            <g key={`${b.label}-${i}`}>
              <rect
                x={xAt(i) - 12}
                y={padT}
                width={24}
                height={innerH}
                fill="transparent"
                style={{ cursor: "pointer" }}
                onClick={() => setSelected(isSel ? null : i)}
              />
              <circle
                cx={xAt(i)}
                cy={paidY}
                r={isSel ? 4.5 : 3}
                fill="#84cc16"
                stroke={isSel ? "#fff" : "none"}
                strokeWidth={1}
                style={{ cursor: "pointer" }}
                onClick={() => setSelected(isSel ? null : i)}
              />
              <circle
                cx={xAt(i)}
                cy={outY}
                r={isSel ? 4.5 : 3}
                fill="#f59e0b"
                stroke={isSel ? "#fff" : "none"}
                strokeWidth={1}
                style={{ cursor: "pointer" }}
                onClick={() => setSelected(isSel ? null : i)}
              />
              <text
                x={xAt(i)}
                y={height - 4}
                textAnchor="middle"
                fill={isSel ? "var(--color-main)" : "rgba(200,200,200,0.75)"}
                fontSize={9}
                fontWeight={isSel ? 700 : 400}
              >
                {b.label}
              </text>
            </g>
          );
        })}
      </svg>
      {active ? (
        <Box
          mt={6}
          p={8}
          style={{
            borderRadius: 6,
            background: "rgba(255,255,255,0.06)",
            border: "1px solid rgba(255,255,255,0.1)",
          }}
        >
          <Text fz={10} fw={600} c="white" mb={4}>
            {active.label}
          </Text>
          <Text fz={10} c="#84cc16">
            {paidLabel}: {active.paidCount} · {formatMoney(active.paidSum)}
          </Text>
          <Text fz={10} c="#f59e0b">
            {outstandingLabel}: {active.outstandingCount} · {formatMoney(active.outstandingSum)}
          </Text>
        </Box>
      ) : (
        <Text fz={9} c="dimmed" mt={4}>
          {tapHint}
        </Text>
      )}
      <Group gap="md" mt={4}>
        <Group gap={6}>
          <Box w={10} h={3} bg="#84cc16" style={{ borderRadius: 2 }} />
          <Text fz={10} c="dimmed">
            {paidLabel}
          </Text>
        </Group>
        <Group gap={6}>
          <Box w={10} h={3} bg="#f59e0b" style={{ borderRadius: 2 }} />
          <Text fz={10} c="dimmed">
            {outstandingLabel}
          </Text>
        </Group>
      </Group>
    </Box>
  );
}
