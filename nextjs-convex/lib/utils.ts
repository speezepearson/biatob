// Format cents as dollars
export function formatCents(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`;
}

// Format probability as percentage
export function formatProbability(p: number): string {
  return `${(p * 100).toFixed(0)}%`;
}

// Format date for display
export function formatDate(timestamp: number): string {
  return new Date(timestamp).toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

// Format date with time
export function formatDateTime(timestamp: number): string {
  return new Date(timestamp).toLocaleString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

// Format relative time
export function formatRelativeTime(timestamp: number): string {
  const now = Date.now();
  const diff = timestamp - now;
  const absDiff = Math.abs(diff);

  const minutes = Math.floor(absDiff / (1000 * 60));
  const hours = Math.floor(absDiff / (1000 * 60 * 60));
  const days = Math.floor(absDiff / (1000 * 60 * 60 * 24));

  if (diff > 0) {
    // Future
    if (days > 0) return `in ${days} day${days === 1 ? "" : "s"}`;
    if (hours > 0) return `in ${hours} hour${hours === 1 ? "" : "s"}`;
    if (minutes > 0) return `in ${minutes} minute${minutes === 1 ? "" : "s"}`;
    return "soon";
  } else {
    // Past
    if (days > 0) return `${days} day${days === 1 ? "" : "s"} ago`;
    if (hours > 0) return `${hours} hour${hours === 1 ? "" : "s"} ago`;
    if (minutes > 0) return `${minutes} minute${minutes === 1 ? "" : "s"} ago`;
    return "just now";
  }
}

// Check if a prediction is still open for betting
export function isBettingOpen(closesAt: number): boolean {
  return closesAt > Date.now();
}

// Get resolution status text
export function getResolutionText(
  resolution: "none_yet" | "yes" | "no" | "invalid" | null
): string {
  if (!resolution || resolution === "none_yet") return "Unresolved";
  if (resolution === "yes") return "Resolved YES";
  if (resolution === "no") return "Resolved NO";
  if (resolution === "invalid") return "Resolved INVALID";
  return "Unknown";
}

// Get resolution color class
export function getResolutionColorClass(
  resolution: "none_yet" | "yes" | "no" | "invalid" | null
): string {
  if (!resolution || resolution === "none_yet") return "text-gray-500";
  if (resolution === "yes") return "text-green-600";
  if (resolution === "no") return "text-red-600";
  if (resolution === "invalid") return "text-yellow-600";
  return "text-gray-500";
}

// Calculate expected value for a bet
export function calculateExpectedValue(
  bettorStakeCents: number,
  creatorStakeCents: number,
  probability: number,
  bettorIsSkeptic: boolean
): number {
  // If skeptic: wins if NO (probability 1-p), loses if YES (probability p)
  // If believer: wins if YES (probability p), loses if NO (probability 1-p)
  const winProbability = bettorIsSkeptic ? 1 - probability : probability;
  return winProbability * creatorStakeCents - (1 - winProbability) * bettorStakeCents;
}

// Generate a cryptographically secure URL-safe ID (lowercase alphanumeric only)
export function generateId(length: number = 12): string {
  const chars = "abcdefghijklmnopqrstuvwxyz0123456789";
  const randomBytes = new Uint8Array(length);
  crypto.getRandomValues(randomBytes);
  let result = "";
  for (let i = 0; i < length; i++) {
    result += chars[randomBytes[i] % chars.length];
  }
  return result;
}
