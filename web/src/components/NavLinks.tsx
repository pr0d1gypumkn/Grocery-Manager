"use client";
import { usePathname } from "next/navigation";

const LINKS = [
  ["/", "Plan"],
  ["/recipes", "Recipes"],
  ["/groceries", "Groceries"],
  ["/pantry", "Pantry"],
  ["/prep", "Prep"],
  ["/settings", "Settings"],
];

export function NavLinks() {
  const path = usePathname();
  return (
    <>
      {LINKS.map(([href, label]) => (
        <a key={href} href={href} className={`item ${path === href || (href !== "/" && path.startsWith(href)) ? "active" : ""}`}>{label}</a>
      ))}
    </>
  );
}
