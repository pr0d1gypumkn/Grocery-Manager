import { FlippFlyerSource, InstacartSource, KrogerSource, PCExpressSource, WalmartSource } from "./adapters";
import { MockPriceSource } from "./mock";
import type { ListLine, PriceQuote, PriceSource, Region } from "./source";
import { ingredientKey } from "../ingredients";

// Add a region or a store here; nothing else in the app hardcodes a retailer.
export function sourcesFor(region: Region): PriceSource[] {
  const common: PriceSource[] = [new FlippFlyerSource(region), new InstacartSource(region), new WalmartSource(region)];
  const regional: PriceSource[] = region === "CA" ? [new PCExpressSource()] : [new KrogerSource()];
  return [...common, ...regional, new MockPriceSource(region)];
}

export function checkoutProvidersFor(region: Region): PriceSource[] {
  return sourcesFor(region).filter((source) => source.supportsCheckout && source.checkoutURL);
}

/** Best (cheapest) quote per line across every configured source. */
export async function bestQuotes(region: Region, lines: ListLine[]): Promise<Map<string, PriceQuote>> {
  const best = new Map<string, PriceQuote>();
  for (const source of sourcesFor(region)) {
    let quotes: PriceQuote[] = [];
    try {
      quotes = await source.quotes(lines);
    } catch (error) {
      console.warn(`[prices] ${source.key} failed:`, error);
      continue;
    }
    for (const quote of quotes) {
      const current = best.get(quote.itemKey);
      if (!current || quote.priceCents < current.priceCents) best.set(quote.itemKey, quote);
    }
  }
  return best;
}

export interface PricedLine extends ListLine {
  quote?: PriceQuote;
}

export async function priceList(region: Region, lines: ListLine[]): Promise<{ lines: PricedLine[]; totalCents: number; currency: string; quotedCount: number }> {
  const quotes = await bestQuotes(region, lines);
  const priced = lines.map((line) => ({ ...line, quote: quotes.get(ingredientKey(line.name)) }));
  const totalCents = priced.reduce((sum, line) => sum + (line.quote?.priceCents ?? 0), 0);
  return { lines: priced, totalCents, currency: region === "CA" ? "CAD" : "USD", quotedCount: priced.filter((l) => l.quote).length };
}
