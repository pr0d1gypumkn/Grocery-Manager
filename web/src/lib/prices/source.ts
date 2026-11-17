import { ingredientKey } from "../ingredients";

// Pluggable price layer. Each region has an ordered list of sources; the first one that
// returns a quote for an item wins. Real retailer and flyer adapters slot in here once
// partnership keys exist; until then MockPriceSource keeps the feature demoable.

export type Region = "US" | "CA";

export interface PriceQuote {
  storeKey: string;
  storeName: string;
  itemKey: string;
  label: string;
  priceCents: number;
  currency: string;
  quantity: number;
  unit: string;
  isSale: boolean;
  validTo: Date;
  source: string;
}

export interface ListLine {
  name: string;
  quantity: number;
  unit: string;
}

export interface PriceSource {
  readonly key: string;
  readonly name: string;
  readonly region: Region;
  readonly sourceKind: "flyer" | "api" | "mock";
  /** Whether a list can be sent to this retailer for checkout. */
  readonly supportsCheckout: boolean;
  /** Returns a quote per line it knows about; unknown items are simply omitted. */
  quotes(lines: ListLine[], options?: { storeKey?: string }): Promise<PriceQuote[]>;
  /** Builds a deep link / cart URL for checkout, when supported. */
  checkoutURL?(lines: ListLine[]): Promise<string>;
}

export function lineKey(line: ListLine): string {
  return ingredientKey(line.name);
}
