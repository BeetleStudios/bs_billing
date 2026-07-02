export type Bill = {
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

export type TrendBucket = {
  label: string;
  paidCount: number;
  paidSum: number;
  outstandingCount: number;
  outstandingSum: number;
};

export type LeaderboardRow = {
  issuerId: string;
  issuerName: string;
  billCount: number;
  billSum: number;
};

export type ApiResult<T> = { success: boolean; data?: T; error?: string };

export type TrendPeriod = "day" | "week" | "month";
