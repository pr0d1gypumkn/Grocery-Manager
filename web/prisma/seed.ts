import { PrismaClient } from "@prisma/client";

// Demo household with a Plus subscription so the web app shows every feature on day one.
const prisma = new PrismaClient();

async function main() {
  const user = await prisma.user.upsert({
    where: { email: "demo@mealy.local" },
    update: {},
    create: { email: "demo@mealy.local", region: "CA", currency: "CAD", unitSystem: "metric", weeklyBudgetCents: 15000 },
  });
  await prisma.subscription.upsert({
    where: { providerSubscriptionId: "demo-plus" },
    update: { currentPeriodEnd: new Date(Date.now() + 365 * 86400 * 1000) },
    create: { userId: user.id, provider: "stripe", providerSubscriptionId: "demo-plus", productId: "demo-yearly", period: "yearly", status: "active", currentPeriodEnd: new Date(Date.now() + 365 * 86400 * 1000) },
  });
  let household = await prisma.household.findFirst({ where: { ownerId: user.id } });
  if (!household) {
    household = await prisma.household.create({
      data: {
        name: "Demo home",
        ownerId: user.id,
        inviteCode: "DEMO1234",
        members: { create: [{ userId: user.id, name: "Alex", role: "owner" }, { name: "Sam" }, { name: "Riley", portionMultiplier: 0.5 }] },
        locations: { create: [{ name: "Pantry", icon: "cabinet.fill" }, { name: "Fridge", icon: "refrigerator.fill" }, { name: "Freezer", icon: "snowflake" }] },
      },
    });
  }
  const locations = await prisma.pantryLocation.findMany({ where: { householdId: household.id } });
  const loc = (name: string) => locations.find((l) => l.name === name)?.id;
  const days = (n: number) => new Date(Date.now() + n * 86400 * 1000);

  if ((await prisma.recipe.count({ where: { householdId: household.id } })) === 0) {
    const recipes = [
      { name: "Lemon Garlic Chicken Bowls", servings: 4, prepMinutes: 15, cookMinutes: 30, tags: "dinner, high-protein, meal-prep", instructions: "1. Preheat the oven to 425°F.\n2. Mince the garlic and zest the lemon.\n3. Roast the chicken for 25 minutes.\n4. Boil the rice for 30 minutes.\n5. Serve with lemon.", ingredients: [["Chicken thighs", 700, "g"], ["Brown rice", 300, "g"], ["Broccoli", 1, "item"], ["Garlic", 4, "item"], ["Lemons", 1, "item"], ["Olive oil", 2, "tbsp"]] },
      { name: "Chickpea Spinach Curry", servings: 4, prepMinutes: 10, cookMinutes: 25, tags: "vegetarian, dinner, freezer-friendly", instructions: "1. Dice the onion and mince the garlic.\n2. Cook the onion for 5 minutes.\n3. Simmer chickpeas, tomatoes and coconut milk for 15 minutes.\n4. Stir in spinach.", ingredients: [["Chickpeas", 2, "item"], ["Spinach", 200, "g"], ["Onions", 1, "item"], ["Garlic", 3, "item"], ["Canned tomatoes", 1, "item"], ["Coconut milk", 400, "ml"], ["Curry powder", 2, "tbsp"], ["Brown rice", 300, "g"]] },
      { name: "Veggie Fried Rice", servings: 4, prepMinutes: 10, cookMinutes: 15, tags: "quick, vegetarian, leftovers", instructions: "1. Dice the carrots.\n2. Scramble the eggs.\n3. Stir-fry everything for 5 minutes.", ingredients: [["Brown rice", 300, "g"], ["Eggs", 3, "item"], ["Carrots", 2, "item"], ["Frozen peas", 150, "g"], ["Green onions", 3, "item"], ["Soy sauce", 3, "tbsp"]] },
      { name: "Overnight Oats", servings: 2, prepMinutes: 5, cookMinutes: 0, tags: "breakfast, no-cook", instructions: "1. Mix everything in jars.\n2. Refrigerate overnight.", ingredients: [["Rolled oats", 100, "g"], ["Milk", 250, "ml"], ["Greek yogurt", 100, "g"], ["Honey", 1, "tbsp"], ["Blueberries", 100, "g"]] },
      { name: "Black Bean Quinoa Salad", servings: 4, prepMinutes: 15, cookMinutes: 15, tags: "lunch, vegan, meal-prep", instructions: "1. Boil the quinoa for 15 minutes.\n2. Dice the pepper.\n3. Toss with lime and oil; chill for 30 minutes.", ingredients: [["Quinoa", 200, "g"], ["Black beans", 1, "item"], ["Bell peppers", 1, "item"], ["Corn", 150, "g"], ["Lime", 2, "item"], ["Cilantro", 1, "item"], ["Olive oil", 3, "tbsp"]] },
    ];
    for (const recipe of recipes) {
      await prisma.recipe.create({ data: { householdId: household.id, name: recipe.name, servings: recipe.servings, prepMinutes: recipe.prepMinutes, cookMinutes: recipe.cookMinutes, tags: recipe.tags, instructions: recipe.instructions, ingredients: { create: recipe.ingredients.map(([name, quantity, unit], sortOrder) => ({ name: String(name), quantity: Number(quantity), unit: String(unit), sortOrder })) } } });
    }
    const all = await prisma.recipe.findMany({ where: { householdId: household.id } });
    const monday = new Date(); monday.setUTCHours(0, 0, 0, 0); monday.setUTCDate(monday.getUTCDate() - ((monday.getUTCDay() + 6) % 7));
    const plan: [number, string, string][] = [[0, "Breakfast", "Overnight Oats"], [0, "Dinner", "Lemon Garlic Chicken Bowls"], [1, "Lunch", "Black Bean Quinoa Salad"], [1, "Dinner", "Chickpea Spinach Curry"], [2, "Dinner", "Veggie Fried Rice"]];
    for (const [offset, mealType, name] of plan) {
      const recipe = all.find((r) => r.name === name)!;
      const date = new Date(monday); date.setUTCDate(date.getUTCDate() + offset);
      await prisma.mealPlanEntry.create({ data: { householdId: household.id, date, mealType, recipeId: recipe.id, servings: 3 } });
    }
    const pantry: [string, number, string, string, number, string][] = [["Chicken thighs", 900, "g", "Meat", 2, "Fridge"], ["Spinach", 200, "g", "Produce", 2, "Fridge"], ["Eggs", 10, "item", "Dairy", 12, "Fridge"], ["Milk", 1.5, "L", "Dairy", 6, "Fridge"], ["Garlic", 8, "item", "Produce", 30, "Pantry"], ["Onions", 4, "item", "Produce", 21, "Pantry"], ["Brown rice", 1.5, "kg", "Pantry", 365, "Pantry"], ["Olive oil", 500, "ml", "Pantry", 300, "Pantry"], ["Frozen peas", 750, "g", "Frozen", 180, "Freezer"]];
    for (const [name, quantity, unit, category, expiry, location] of pantry) {
      await prisma.pantryItem.create({ data: { householdId: household.id, name, quantity, unit, initialQuantity: quantity, category, expiryDate: days(expiry), locationId: loc(location) } });
    }
    await prisma.groceryItem.createMany({ data: [{ householdId: household.id, name: "Paper towels", quantity: 1, unit: "item", category: "Other" }, { householdId: household.id, name: "Coconut milk", quantity: 400, unit: "ml", category: "Pantry", source: "plan" }] });
  }

  for (const store of [
    { key: "mock-us", name: "Demo store (US)", region: "US", sourceKind: "mock" },
    { key: "mock-ca", name: "Demo store (CA)", region: "CA", sourceKind: "mock" },
    { key: "instacart-us", name: "Instacart", region: "US", sourceKind: "api", supportsCheckout: true },
    { key: "instacart-ca", name: "Instacart", region: "CA", sourceKind: "api", supportsCheckout: true },
    { key: "walmart-us", name: "Walmart", region: "US", sourceKind: "api", supportsCheckout: true },
    { key: "walmart-ca", name: "Walmart", region: "CA", sourceKind: "api", supportsCheckout: true },
    { key: "pcexpress-ca", name: "PC Express", region: "CA", sourceKind: "api", supportsCheckout: true },
    { key: "kroger-us", name: "Kroger", region: "US", sourceKind: "api", supportsCheckout: true },
    { key: "flipp-us", name: "Flipp flyers", region: "US", sourceKind: "flyer" },
    { key: "flipp-ca", name: "Flipp flyers", region: "CA", sourceKind: "flyer" },
  ]) {
    await prisma.store.upsert({ where: { key: store.key }, update: {}, create: store });
  }
  console.log("Seeded demo user demo@mealy.local (Plus, household invite code DEMO1234).");
}

main().finally(() => prisma.$disconnect());
