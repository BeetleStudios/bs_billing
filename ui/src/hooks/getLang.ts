import { fetchNui, isEnvBrowser } from "./useNui";

function normalizeLang(code: string | undefined): string {
  if (!code || code === "") return "en";
  const base = code.toLowerCase().split(/[-_]/)[0];
  if (base === "es" || base === "pt") return base;
  return "en";
}

export async function getLang(): Promise<Record<string, string>> {
  let lang = "en";

  if (!isEnvBrowser()) {
    try {
      const r = (await fetchNui<{ lang?: string }>("getLang")) as { lang?: string };
      lang = normalizeLang(r?.lang);
    } catch {
      lang = "en";
    }
  }

  try {
    const response = await fetch(`locales/${lang}.json`);
    if (response.ok) {
      return await response.json();
    }
  } catch {
    /* missing file */
  }

  try {
    const fallback = await fetch("locales/en.json");
    if (fallback.ok) {
      return await fallback.json();
    }
  } catch {
    /* dev / missing file */
  }

  return {};
}
