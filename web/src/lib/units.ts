// Unit conversion, mirrored from UnitConversion.swift so both sides merge lists identically.

export type Dimension = "count" | "mass" | "volume";

const BASE: Record<string, { dimension: Dimension; factor: number }> = {
  item: { dimension: "count", factor: 1 },
  dozen: { dimension: "count", factor: 12 },
  serving: { dimension: "count", factor: 1 },
  g: { dimension: "mass", factor: 1 },
  kg: { dimension: "mass", factor: 1000 },
  oz: { dimension: "mass", factor: 28.349523125 },
  lb: { dimension: "mass", factor: 453.59237 },
  ml: { dimension: "volume", factor: 1 },
  L: { dimension: "volume", factor: 1000 },
  "fl oz": { dimension: "volume", factor: 29.5735295625 },
  tsp: { dimension: "volume", factor: 4.92892159375 },
  tbsp: { dimension: "volume", factor: 14.78676478125 },
  cup: { dimension: "volume", factor: 236.5882365 },
  pt: { dimension: "volume", factor: 473.176473 },
  qt: { dimension: "volume", factor: 946.352946 },
  gal: { dimension: "volume", factor: 3785.411784 },
  pinch: { dimension: "volume", factor: 0.3080575996 },
  dash: { dimension: "volume", factor: 0.6161151992 },
  smidgen: { dimension: "volume", factor: 0.1540287998 },
};

export const UNITS = Object.keys(BASE);

export function dimensionOf(unit: string): Dimension | undefined {
  return BASE[unit]?.dimension;
}

/** Converts between units of the same dimension; `undefined` when they don't share one. */
export function convert(quantity: number, from: string, to: string): number | undefined {
  const source = BASE[from];
  const target = BASE[to];
  if (!source || !target || source.dimension !== target.dimension) return undefined;
  return (quantity * source.factor) / target.factor;
}

export type UnitSystem = "metric" | "imperial";

/** Picks the unit a reader expects, e.g. 500 g → 1.1 lb for imperial users. */
export function display(quantity: number, unit: string, system: UnitSystem): { quantity: number; unit: string } {
  const dim = dimensionOf(unit);
  if (!dim || dim === "count" || ["tsp", "tbsp", "pinch", "dash", "smidgen"].includes(unit)) return { quantity, unit };
  let target: string | undefined;
  if (system === "metric") {
    if (dim === "mass" && ["oz", "lb"].includes(unit)) target = (convert(quantity, unit, "g") ?? 0) >= 1000 ? "kg" : "g";
    if (dim === "volume" && ["fl oz", "cup", "pt", "qt", "gal"].includes(unit)) target = (convert(quantity, unit, "ml") ?? 0) >= 1000 ? "L" : "ml";
  } else {
    if (dim === "mass" && ["g", "kg"].includes(unit)) target = (convert(quantity, unit, "g") ?? 0) >= 453.59237 ? "lb" : "oz";
    if (dim === "volume" && ["ml", "L"].includes(unit)) {
      const ml = convert(quantity, unit, "ml") ?? 0;
      target = ml >= 946 ? "qt" : ml >= 59 ? "cup" : "fl oz";
    }
  }
  if (!target) return { quantity, unit };
  const converted = convert(quantity, unit, target);
  if (converted === undefined) return { quantity, unit };
  return { quantity: Math.round(converted * 100) / 100, unit: target };
}

export function formatQuantity(quantity: number): string {
  return Number.isInteger(quantity) ? String(quantity) : quantity.toFixed(2).replace(/\.?0+$/, "");
}
