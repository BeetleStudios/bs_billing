import { atom } from "recoil";

export const Lang = atom<Record<string, string>>({
  key: "lang",
  default: {},
});
