import { FEATURES, type Feature } from "@/lib/entitlements";

const SUMMARY: Record<Feature, string> = {
  price_aware_shopping: "See what your list will cost, plan around flyer prices, and set a weekly budget.",
  automatic_planning: "Get a full week planned from your tastes, schedule, pantry and budget.",
  recipe_suggestions: "Discover recipes you haven't saved, matched to your tastes and pantry.",
  social_import: "Pull recipes out of TikTok, Instagram and YouTube links, screenshots and photos.",
  household_sharing: "Share plans, lists and the pantry in real time, with portions per person.",
  checkout_links: "Send your list to Instacart, PC Express, Walmart and more.",
};

/** Gentle paywall: explains the feature and links to billing; nothing free is blocked. */
export function Locked({ feature }: { feature: Feature }) {
  return (
    <div className="lock">
      <strong>{FEATURES[feature].title}</strong> <span className="badge purple">Plus</span>
      <p className="muted" style={{ margin: "6px 0 10px" }}>{SUMMARY[feature]}</p>
      <a className="btn primary" href="/settings#billing">See plans</a>
    </div>
  );
}
