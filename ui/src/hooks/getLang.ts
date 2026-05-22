export async function getLang(): Promise<Record<string, string>> {
  try {
    const response = await fetch("locales/en.json");
    if (response.ok) {
      return await response.json();
    }
  } catch {
    /* dev / missing file */
  }
  return {};
}
