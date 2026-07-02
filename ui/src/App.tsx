import { useCallback, useEffect, useState } from "react";
import { MantineProvider } from "@mantine/core";
import { useSetRecoilState } from "recoil";
import { Lang } from "./reducers/atoms";
import { getLang } from "./hooks/getLang";
import { fetchNui, isEnvBrowser, useNuiEvent } from "./hooks/useNui";
import { MainApp } from "./components/MainApp";
import { IncomingBillAlert, type IncomingBillPayload } from "./components/IncomingBillAlert";
import shell from "./components/nuiShell.module.css";
import "./App.css";
import "@mantine/core/styles.css";

type TabId = "outstanding" | "history" | "create" | "manage";

export default function App() {
  const setLang = useSetRecoilState(Lang);
  const [ready, setReady] = useState(false);
  const [panelOpen, setPanelOpen] = useState(isEnvBrowser());
  const [initialTab, setInitialTab] = useState<TabId>("outstanding");
  const [incoming, setIncoming] = useState<IncomingBillPayload | null>(
    isEnvBrowser()
      ? {
          amount: 500,
          issuerName: "LSPD",
          reason: "Parking fine",
          billId: 1001,
          openKey: "E",
          dismissKey: "BACK",
        }
      : null
  );

  useEffect(() => {
    (async () => {
      setLang(await getLang());
      setReady(true);
    })();
  }, [setLang]);

  useNuiEvent<{ tab?: TabId }>("open", (data) => {
    setIncoming(null);
    setInitialTab(data?.tab ?? "outstanding");
    setPanelOpen(true);
  });

  useNuiEvent("close", () => {
    setPanelOpen(false);
  });

  useNuiEvent("clearIncoming", () => {
    setIncoming(null);
  });

  useNuiEvent<IncomingBillPayload>("incomingBill", (data) => {
    if (data && typeof data === "object") {
      setIncoming(data);
    }
  });

  const handleClose = useCallback(() => {
    setPanelOpen(false);
    if (!isEnvBrowser()) {
      void fetchNui("close");
    }
  }, []);

  const handleDismissAlert = useCallback(() => {
    setIncoming(null);
    if (!isEnvBrowser()) {
      void fetchNui("dismissAlert");
    }
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape" && panelOpen) {
        handleClose();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [panelOpen, handleClose]);

  if (!ready) return null;

  return (
    <MantineProvider defaultColorScheme="dark">
      <div className={shell.root}>
        {incoming && !panelOpen ? (
          <IncomingBillAlert data={incoming} onDismiss={handleDismissAlert} />
        ) : null}
        {panelOpen ? (
          <div className={shell.panelWrap}>
            <div className={shell.panelFrame}>
              <MainApp initialTab={initialTab} onClose={handleClose} />
            </div>
          </div>
        ) : null}
      </div>
    </MantineProvider>
  );
}
