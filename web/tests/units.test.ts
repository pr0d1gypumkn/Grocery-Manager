import { describe, expect, it } from "vitest";
import { convert, display } from "@/lib/units";

describe("unit conversion", () => {
  it("converts within a dimension", () => {
    expect(convert(1, "kg", "g")).toBe(1000);
    expect(convert(1, "lb", "oz")).toBeCloseTo(16, 6);
    expect(convert(1, "cup", "tbsp")).toBeCloseTo(16, 6);
    expect(convert(2, "dozen", "item")).toBe(24);
  });
  it("refuses cross-dimension conversions", () => {
    expect(convert(1, "g", "ml")).toBeUndefined();
    expect(convert(1, "item", "g")).toBeUndefined();
    expect(convert(1, "banana", "g")).toBeUndefined();
  });
  it("displays in the reader's system", () => {
    expect(display(500, "g", "imperial")).toEqual({ quantity: 1.1, unit: "lb" });
    expect(display(2, "cup", "metric")).toEqual({ quantity: 473.18, unit: "ml" });
    expect(display(2, "tbsp", "metric")).toEqual({ quantity: 2, unit: "tbsp" });
  });
});
