// Social recipe import. TikTok, Instagram and YouTube all need partner API access for
// reliable caption/transcript extraction; until keys exist we use their public oEmbed
// endpoints (title + author) and the page's own schema.org markup when present.

export interface SocialImportResult {
  platform: "tiktok" | "instagram" | "youtube" | "web" | "unknown";
  title: string;
  author?: string;
  thumbnailUrl?: string;
  description?: string;
  /** True when a full recipe (ingredients + steps) was extracted. */
  complete: boolean;
  recipe?: { name: string; ingredientLines: string[]; instructions: string[]; servings?: number };
  note: string;
}

export function platformFor(url: URL): SocialImportResult["platform"] {
  const host = url.hostname.replace(/^www\./, "");
  if (host.includes("tiktok.com")) return "tiktok";
  if (host.includes("instagram.com")) return "instagram";
  if (host.includes("youtube.com") || host === "youtu.be") return "youtube";
  return "web";
}

function oembedEndpoint(platform: SocialImportResult["platform"], url: string): string | null {
  switch (platform) {
    case "tiktok": return `https://www.tiktok.com/oembed?url=${encodeURIComponent(url)}`;
    case "youtube": return `https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(url)}`;
    case "instagram": return process.env.META_OEMBED_TOKEN ? `https://graph.facebook.com/v19.0/instagram_oembed?url=${encodeURIComponent(url)}&access_token=${process.env.META_OEMBED_TOKEN}` : null;
    default: return null;
  }
}

export async function importSocial(rawUrl: string): Promise<SocialImportResult> {
  const url = new URL(rawUrl);
  const platform = platformFor(url);
  const endpoint = oembedEndpoint(platform, url.toString());
  let title = "";
  let author: string | undefined;
  let thumbnailUrl: string | undefined;
  if (endpoint) {
    try {
      const response = await fetch(endpoint, { headers: { Accept: "application/json" }, signal: AbortSignal.timeout(8000) });
      if (response.ok) {
        const data = (await response.json()) as { title?: string; author_name?: string; thumbnail_url?: string };
        title = data.title ?? "";
        author = data.author_name;
        thumbnailUrl = data.thumbnail_url;
      }
    } catch {
      // fall through to the "needs partner API" note
    }
  }
  const needsKey = platform === "instagram" ? "Instagram requires a Meta oEmbed/Graph token (META_OEMBED_TOKEN)." : platform === "tiktok" ? "Full captions need the TikTok Research/Display API." : platform === "youtube" ? "Descriptions and transcripts need the YouTube Data API (YOUTUBE_API_KEY)." : "";
  return {
    platform,
    title: title || url.hostname,
    author,
    thumbnailUrl,
    complete: false,
    note: `Found the post${author ? ` by ${author}` : ""}. ${needsKey} The app will fall back to on-device extraction from the caption you paste or a screenshot.`.trim(),
  };
}
