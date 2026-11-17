import { convert } from "../units";
import { ingredientKey } from "../ingredients";
import type { ListLine, PriceQuote, PriceSource, Region } from "./source";

// Representative shelf prices per 100 g / per item, in the local currency, so the demo
// shows believable totals. Replace with real feeds; keep the shape.

interface MockPrice { per: "g" | "ml" | "item"; cents: number; label: string }

const US_PRICES: Record<string, MockPrice> = {
  "chicken thigh": { per: "g", cents: 0.66, label: "Chicken thighs, bone-in" },
  "chicken breast": { per: "g", cents: 0.88, label: "Chicken breast" },
  "ground beef": { per: "g", cents: 1.2, label: "Ground beef 80/20" },
  salmon: { per: "item", cents: 699, label: "Salmon fillet" },
  "salmon fillet": { per: "item", cents: 699, label: "Salmon fillet" },
  egg: { per: "item", cents: 32, label: "Large eggs" },
  milk: { per: "ml", cents: 0.11, label: "Whole milk" },
  "greek yogurt": { per: "g", cents: 0.8, label: "Greek yogurt" },
  "cheddar cheese": { per: "g", cents: 1.1, label: "Cheddar block" },
  parmesan: { per: "g", cents: 2.2, label: "Parmesan wedge" },
  butter: { per: "g", cents: 1.0, label: "Butter" },
  "brown rice": { per: "g", cents: 0.3, label: "Brown rice" },
  rice: { per: "g", cents: 0.25, label: "Long grain rice" },
  quinoa: { per: "g", cents: 0.7, label: "Quinoa" },
  pasta: { per: "g", cents: 0.3, label: "Pasta" },
  "rolled oat": { per: "g", cents: 0.3, label: "Rolled oats" },
  tortilla: { per: "item", cents: 45, label: "Flour tortillas" },
  bread: { per: "item", cents: 349, label: "Bread loaf" },
  onion: { per: "item", cents: 89, label: "Yellow onion" },
  garlic: { per: "item", cents: 20, label: "Garlic clove" },
  carrot: { per: "item", cents: 25, label: "Carrots" },
  "bell pepper": { per: "item", cents: 129, label: "Bell pepper" },
  broccoli: { per: "item", cents: 249, label: "Broccoli crown" },
  spinach: { per: "g", cents: 1.5, label: "Baby spinach" },
  "romaine lettuce": { per: "item", cents: 249, label: "Romaine hearts" },
  lemon: { per: "item", cents: 69, label: "Lemon" },
  lime: { per: "item", cents: 39, label: "Lime" },
  cilantro: { per: "item", cents: 99, label: "Cilantro bunch" },
  basil: { per: "item", cents: 299, label: "Fresh basil" },
  ginger: { per: "g", cents: 0.6, label: "Ginger root" },
  "green onion": { per: "item", cents: 25, label: "Green onions" },
  chickpea: { per: "item", cents: 129, label: "Chickpeas, can" },
  "black bean": { per: "item", cents: 119, label: "Black beans, can" },
  "canned tomato": { per: "item", cents: 149, label: "Diced tomatoes, can" },
  "coconut milk": { per: "ml", cents: 0.6, label: "Coconut milk" },
  "olive oil": { per: "ml", cents: 1.6, label: "Olive oil" },
  "soy sauce": { per: "ml", cents: 0.8, label: "Soy sauce" },
  "curry powder": { per: "ml", cents: 5, label: "Curry powder" },
  cumin: { per: "ml", cents: 5, label: "Ground cumin" },
  honey: { per: "ml", cents: 1.5, label: "Honey" },
  blueberry: { per: "g", cents: 1.8, label: "Blueberries" },
  "chia seed": { per: "ml", cents: 3, label: "Chia seeds" },
  corn: { per: "g", cents: 0.4, label: "Frozen corn" },
  "frozen pea": { per: "g", cents: 0.35, label: "Frozen peas" },
  "vegetable broth": { per: "ml", cents: 0.3, label: "Vegetable broth" },
  "sparkling water": { per: "item", cents: 59, label: "Sparkling water" },
  "paper towel": { per: "item", cents: 899, label: "Paper towels" },
};

const SALES: Record<Region, Record<string, number>> = {
  US: { "chicken thigh": 0.75, salmon: 0.8, "salmon fillet": 0.8, broccoli: 0.7 },
  CA: { "ground beef": 0.7, "bell pepper": 0.6, "greek yogurt": 0.8 },
};

const CA_MULTIPLIER = 1.35;

export class MockPriceSource implements PriceSource {
  readonly sourceKind = "mock" as const;
  readonly supportsCheckout = false;

  constructor(readonly region: Region, readonly key = region === "CA" ? "mock-ca" : "mock-us", readonly name = region === "CA" ? "Demo store (CA)" : "Demo store (US)") {}

  async quotes(lines: ListLine[]): Promise<PriceQuote[]> {
    const currency = this.region === "CA" ? "CAD" : "USD";
    const validTo = new Date(Date.now() + 7 * 86400 * 1000);
    return lines.flatMap((line) => {
      const key = ingredientKey(line.name);
      const tokens = key.split(" ");
      const fuzzyKey = Object.keys(US_PRICES).find((k) => k.split(" ").every((t) => tokens.includes(t)));
      const price = US_PRICES[key] ?? (fuzzyKey ? US_PRICES[fuzzyKey] : undefined);
      if (!price) return [];
      let amount: number | undefined;
      if (price.per === "item") amount = ["item", "dozen", "serving"].includes(line.unit) ? convert(line.quantity, line.unit, "item") : 1;
      else amount = convert(line.quantity, line.unit, price.per) ?? (price.per === "g" ? convert(line.quantity, line.unit, "ml") : convert(line.quantity, line.unit, "g"));
      if (amount === undefined) amount = 1;
      const regionFactor = this.region === "CA" ? CA_MULTIPLIER : 1;
      const saleFactor = SALES[this.region][key] ?? 1;
      const cents = Math.max(Math.round(price.cents * amount * regionFactor * saleFactor), 1);
      return [{
        storeKey: this.key,
        storeName: this.name,
        itemKey: key,
        label: price.label,
        priceCents: cents,
        currency,
        quantity: line.quantity,
        unit: line.unit,
        isSale: saleFactor < 1,
        validTo,
        source: "mock",
      }];
    });
  }
}
