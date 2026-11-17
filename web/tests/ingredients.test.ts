import { describe, expect, it } from "vitest";
import { consume, ingredientKey, mergeRequirements, sameIngredient, shortfalls } from "@/lib/ingredients";

const future = new Date(Date.now() + 10 * 86400 * 1000);

describe("ingredient merging", () => {
  it("normalises names", () => {
    expect(ingredientKey("Diced Red Onions")).toBe("red onion");
    expect(sameIngredient("scallions", "green onion")).toBe(true);
    expect(sameIngredient("fresh cilantro, chopped", "Cilantro")).toBe(true);
    expect(sameIngredient("green onion", "onion")).toBe(false);
  });
  it("merges same ingredients across compatible units", () => {
    const merged = mergeRequirements([
      { name: "Onion", quantity: 1, unit: "item" },
      { name: "onions", quantity: 2, unit: "item" },
      { name: "Flour", quantity: 200, unit: "g" },
      { name: "flour", quantity: 0.5, unit: "kg" },
      { name: "Milk", quantity: 1, unit: "cup" },
      { name: "milk", quantity: 100, unit: "g" },
    ]);
    expect(merged).toHaveLength(4);
    expect(merged.find((m) => m.name === "Onion")?.quantity).toBe(3);
    expect(merged.find((m) => m.name === "Flour")?.quantity).toBe(700);
  });
  it("computes shortfalls against stock", () => {
    const stock = [{ name: "Rice", quantity: 1, unit: "kg", expiryDate: future }, { name: "Chicken breast", quantity: 300, unit: "g", expiryDate: future }];
    const lines = shortfalls([{ name: "rice", quantity: 300, unit: "g" }, { name: "chicken breast", quantity: 500, unit: "g" }, { name: "broccoli", quantity: 1, unit: "item" }], stock);
    expect(lines.map((l) => l.name)).toEqual(["chicken breast", "broccoli"]);
    expect(lines[0].missing).toBe(200);
  });
});

describe("pantry deduction", () => {
  it("uses soonest-expiring stock first and converts units", () => {
    const old = { name: "Milk", quantity: 1, unit: "cup", expiryDate: new Date(Date.now() + 86400 * 1000) };
    const fresh = { name: "Milk", quantity: 1, unit: "L", expiryDate: future };
    const short = consume([{ name: "milk", quantity: 500, unit: "ml" }], [fresh, old]);
    expect(short).toEqual([]);
    expect(old.quantity).toBeCloseTo(0, 6);
    expect(fresh.quantity).toBeCloseTo(1 - (500 - 236.5882365) / 1000, 6);
  });
  it("reports what it could not cover", () => {
    const eggs = { name: "Eggs", quantity: 2, unit: "item", expiryDate: future };
    expect(consume([{ name: "eggs", quantity: 3, unit: "item" }], [eggs])).toEqual(["eggs"]);
    expect(eggs.quantity).toBe(0);
  });
});
