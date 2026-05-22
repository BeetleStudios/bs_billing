import { useEffect, useRef } from "react";

export function isEnvBrowser(): boolean {
  return !(window as unknown as { invokeNative?: unknown }).invokeNative;
}

export function getResourceName(): string {
  return (
    (window as unknown as { GetParentResourceName?: () => string }).GetParentResourceName?.() ??
    "bs_billing"
  );
}

export async function fetchNui<T>(eventName: string, data?: unknown): Promise<T> {
  if (isEnvBrowser()) {
    return {} as T;
  }
  const resp = await fetch(`https://${getResourceName()}/${eventName}`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify(data ?? {}),
  });
  return resp.json();
}

type NuiHandler<T> = (data: T) => void;

export function useNuiEvent<T>(action: string, handler: NuiHandler<T>) {
  const saved = useRef(handler);
  saved.current = handler;

  useEffect(() => {
    const listener = (event: MessageEvent) => {
      const msg = event.data;
      if (!msg || msg.action !== action) return;
      saved.current(msg.data as T);
    };
    window.addEventListener("message", listener);
    return () => window.removeEventListener("message", listener);
  }, [action]);
}
