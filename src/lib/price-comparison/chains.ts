import type { BarcodeProduct } from "@/types/domain";

export type ChainKey = "shufersal" | "rami_levy" | "carrefour" | "super_pharm" | "osher_ad";

export type ChainMeta = {
  key: ChainKey;
  name: string;
  /** Which barcode_products column holds this chain's price — the only
   * thing that needs updating when a new chain's data is imported. */
  priceColumn: keyof Pick<
    BarcodeProduct,
    "price_shufersal" | "price_rami_levy" | "price_carrefour" | "price_super_pharm" | "price_osher_ad"
  >;
  /** Flat brand-ish color for the chain's badge — no logo assets available. */
  color: string;
  initial: string;
};

export const CHAINS: ChainMeta[] = [
  { key: "shufersal", name: "שופרסל", priceColumn: "price_shufersal", color: "bg-red-600", initial: "ש" },
  { key: "rami_levy", name: "רמי לוי", priceColumn: "price_rami_levy", color: "bg-blue-700", initial: "ר" },
  { key: "carrefour", name: "קרפור", priceColumn: "price_carrefour", color: "bg-sky-600", initial: "ק" },
  { key: "super_pharm", name: "סופר פארם", priceColumn: "price_super_pharm", color: "bg-slate-700", initial: "ס" },
  { key: "osher_ad", name: "אושר עד", priceColumn: "price_osher_ad", color: "bg-emerald-600", initial: "א" },
];

/** The general grocery-run list ("קניות בסופר") skips Super-Pharm — it's a
 * pharmacy/drugstore, not a supermarket, so comparing a grocery basket
 * against it is mostly noise. A list that's actually Super-Pharm's own
 * (named after the chain) still compares against everyone as normal. */
export function excludedChainsForSection(sectionName: string): ChainKey[] {
  return sectionName.trim() === "קניות בסופר" ? ["super_pharm"] : [];
}
