import type { ListLine, PriceQuote, PriceSource, Region } from "./source";

// Real-world adapters. Each needs a partnership or API key (see README). Until the key is
// configured they report `isConfigured() === false` and the registry skips them.

export abstract class KeyedSource implements PriceSource {
  abstract readonly key: string;
  abstract readonly name: string;
  abstract readonly region: Region;
  abstract readonly sourceKind: "flyer" | "api";
  abstract readonly supportsCheckout: boolean;
  protected abstract readonly envKey: string;

  isConfigured(): boolean {
    return Boolean(process.env[this.envKey]);
  }

  async quotes(_lines: ListLine[]): Promise<PriceQuote[]> {
    if (!this.isConfigured()) return [];
    throw new Error(`${this.name} adapter: API client not implemented yet (key present).`);
  }
}

/** Flipp aggregates weekly flyers for most US and Canadian grocers. Needs a Flipp partner key. */
export class FlippFlyerSource extends KeyedSource {
  readonly key: string;
  readonly name = "Flipp flyers";
  readonly sourceKind = "flyer" as const;
  readonly supportsCheckout = false;
  protected readonly envKey = "FLIPP_API_KEY";
  constructor(readonly region: Region) {
    super();
    this.key = `flipp-${region.toLowerCase()}`;
  }
}

/** Instacart Developer Platform: prices via retailer catalog, plus "shopping list" checkout links. */
export class InstacartSource extends KeyedSource {
  readonly key: string;
  readonly name = "Instacart";
  readonly sourceKind = "api" as const;
  readonly supportsCheckout = true;
  protected readonly envKey = "INSTACART_API_KEY";
  constructor(readonly region: Region) {
    super();
    this.key = `instacart-${region.toLowerCase()}`;
  }

  async checkoutURL(lines: ListLine[]): Promise<string> {
    // Instacart's Developer Platform "Create shopping list page" endpoint returns a hosted
    // page for a list of line items. Without a key, we fall back to a search deep link.
    if (!this.isConfigured()) {
      const query = encodeURIComponent(lines.map((l) => l.name).join(", "));
      return `https://www.instacart.com/store/s?k=${query}`;
    }
    throw new Error("Instacart checkout: API client not implemented yet (key present).");
  }
}

/** Walmart (US affiliate API / CA site). Checkout via search deep links only. */
export class WalmartSource extends KeyedSource {
  readonly key: string;
  readonly name = "Walmart";
  readonly sourceKind = "api" as const;
  readonly supportsCheckout = true;
  protected readonly envKey = "WALMART_API_KEY";
  constructor(readonly region: Region) {
    super();
    this.key = `walmart-${region.toLowerCase()}`;
  }

  async checkoutURL(lines: ListLine[]): Promise<string> {
    const host = this.region === "CA" ? "www.walmart.ca" : "www.walmart.com";
    return `https://${host}/search?q=${encodeURIComponent(lines.map((l) => l.name).join(" "))}`;
  }
}

/** PC Express (Loblaw, Canada). No public API: deep link into their search. */
export class PCExpressSource extends KeyedSource {
  readonly key = "pcexpress-ca";
  readonly name = "PC Express";
  readonly region = "CA" as const;
  readonly sourceKind = "api" as const;
  readonly supportsCheckout = true;
  protected readonly envKey = "PCEXPRESS_API_KEY";

  async checkoutURL(lines: ListLine[]): Promise<string> {
    return `https://www.pcexpress.ca/search?search-bar=${encodeURIComponent(lines.map((l) => l.name).join(" "))}`;
  }
}

/** Kroger has a public developer API (products + cart) for US stores. */
export class KrogerSource extends KeyedSource {
  readonly key = "kroger-us";
  readonly name = "Kroger";
  readonly region = "US" as const;
  readonly sourceKind = "api" as const;
  readonly supportsCheckout = true;
  protected readonly envKey = "KROGER_CLIENT_ID";

  async checkoutURL(lines: ListLine[]): Promise<string> {
    return `https://www.kroger.com/search?query=${encodeURIComponent(lines.map((l) => l.name).join(" "))}`;
  }
}
