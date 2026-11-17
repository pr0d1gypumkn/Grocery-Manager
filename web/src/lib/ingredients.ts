import { convert } from "./units";

// A trimmed port of IngredientNameMatcher: lowercase, drop preparation words, apply aliases,
// crude stemming. The iOS side uses the NaturalLanguage lemmatiser, which this approximates.

const PREP_WORDS = new Set([
  "fresh", "frozen", "dried", "dry", "canned", "jarred", "raw", "cooked", "chopped", "diced", "sliced", "minced",
  "grated", "shredded", "crushed", "ground", "melted", "softened", "room", "temperature", "baby", "leaves", "leaf",
  "optional", "organic", "large", "medium", "small",
]);

const ALIASES: Record<string, string> = {
  scallions: "green onion",
  scallion: "green onion",
  coriander: "cilantro",
  aubergine: "eggplant",
  courgette: "zucchini",
  capsicum: "pepper",
};

function stem(token: string): string {
  if (token.endsWith("ies") && token.length > 4) return token.slice(0, -3) + "y";
  if (token.endsWith("es") && token.length > 4) return token.slice(0, -2);
  if (token.endsWith("s") && token.length > 3) return token.slice(0, -1);
  return token;
}

export function ingredientKey(name: string): string {
  return name
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(Boolean)
    .map((token) => ALIASES[token] ?? token)
    .flatMap((token) => token.split(" "))
    .map(stem)
    .filter((token) => !PREP_WORDS.has(token))
    .join(" ");
}

export function sameIngredient(a: string, b: string): boolean {
  return ingredientKey(a) === ingredientKey(b);
}

export interface Requirement {
  name: string;
  quantity: number;
  unit: string;
}

/** Merges requirements for the same ingredient, converting units where possible. */
export function mergeRequirements(requirements: Requirement[]): Requirement[] {
  const merged: Requirement[] = [];
  const keys: string[] = [];
  for (const requirement of requirements) {
    const key = ingredientKey(requirement.name);
    const index = keys.findIndex((k, i) => k === key && convert(1, requirement.unit, merged[i].unit) !== undefined);
    if (index >= 0) {
      merged[index] = { ...merged[index], quantity: merged[index].quantity + (convert(requirement.quantity, requirement.unit, merged[index].unit) ?? 0) };
    } else {
      merged.push({ ...requirement });
      keys.push(key);
    }
  }
  return merged;
}

export interface StockItem {
  name: string;
  quantity: number;
  unit: string;
  expiryDate: Date;
  category?: string;
}

export interface Shortfall extends Requirement {
  available: number;
  missing: number;
}

/** What the pantry can't cover, after merging and unit conversion. */
export function shortfalls(requirements: Requirement[], stock: StockItem[], now = new Date()): Shortfall[] {
  return mergeRequirements(requirements)
    .map((requirement) => {
      const available = stock
        .filter((item) => item.expiryDate >= now && sameIngredient(item.name, requirement.name))
        .reduce((total, item) => total + (convert(item.quantity, item.unit, requirement.unit) ?? 0), 0);
      return { ...requirement, available, missing: Math.max(requirement.quantity - available, 0) };
    })
    .filter((line) => line.missing > 0.0001);
}

/** Deducts requirements from stock, soonest expiry first. Mutates quantities; returns names it couldn't cover. */
export function consume(requirements: Requirement[], stock: StockItem[]): string[] {
  const short: string[] = [];
  for (const requirement of mergeRequirements(requirements)) {
    let remaining = requirement.quantity;
    const candidates = stock
      .filter((item) => item.quantity > 0 && sameIngredient(item.name, requirement.name))
      .sort((a, b) => a.expiryDate.getTime() - b.expiryDate.getTime());
    for (const item of candidates) {
      if (remaining <= 0.0001) break;
      const availableInUnit = convert(item.quantity, item.unit, requirement.unit);
      if (availableInUnit === undefined) continue;
      const used = Math.min(availableInUnit, remaining);
      item.quantity = Math.max(item.quantity - (convert(used, requirement.unit, item.unit) ?? 0), 0);
      remaining -= used;
    }
    if (remaining > 0.0001) short.push(requirement.name);
  }
  return short;
}

export const AISLE_ORDER = ["Produce", "Bakery", "Meat", "Seafood", "Dairy", "Pantry", "Beverages", "Frozen", "Other"];

export function aisleIndex(category: string): number {
  const index = AISLE_ORDER.indexOf(category);
  return index === -1 ? AISLE_ORDER.length : index;
}

export function purchaseQuantity(quantity: number, unit: string): number {
  return ["item", "dozen", "serving"].includes(unit) ? Math.ceil(quantity) : Math.ceil(quantity * 100) / 100;
}
