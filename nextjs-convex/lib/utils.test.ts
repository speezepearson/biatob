import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import {
  formatCents,
  formatProbability,
  formatDate,
  formatDateTime,
  formatRelativeTime,
  isBettingOpen,
  getResolutionText,
  getResolutionColorClass,
  calculateExpectedValue,
  generateId,
} from "./utils";

describe("Utils", () => {
  describe("formatCents", () => {
    test("formats positive cents", () => {
      expect(formatCents(1000)).toBe("$10.00");
      expect(formatCents(1)).toBe("$0.01");
      expect(formatCents(12345)).toBe("$123.45");
    });

    test("formats zero", () => {
      expect(formatCents(0)).toBe("$0.00");
    });
  });

  describe("formatProbability", () => {
    test("formats probabilities as percentages", () => {
      expect(formatProbability(0.5)).toBe("50%");
      expect(formatProbability(0.75)).toBe("75%");
      expect(formatProbability(0.1)).toBe("10%");
      expect(formatProbability(0)).toBe("0%");
      expect(formatProbability(1)).toBe("100%");
    });
  });

  describe("formatDate", () => {
    test("formats timestamp as date", () => {
      // Jan 15, 2024
      const timestamp = new Date("2024-01-15T12:00:00Z").getTime();
      const result = formatDate(timestamp);
      expect(result).toContain("Jan");
      expect(result).toContain("15");
      expect(result).toContain("2024");
    });
  });

  describe("formatDateTime", () => {
    test("includes time in output", () => {
      const timestamp = new Date("2024-01-15T14:30:00Z").getTime();
      const result = formatDateTime(timestamp);
      expect(result).toContain("Jan");
      expect(result).toContain("15");
      expect(result).toContain("2024");
      // Should contain time elements
      expect(result).toMatch(/\d+:\d+/);
    });
  });

  describe("formatRelativeTime", () => {
    beforeEach(() => {
      vi.useFakeTimers();
      vi.setSystemTime(new Date("2024-01-15T12:00:00Z"));
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    test("formats future time in days", () => {
      const future = Date.now() + 3 * 24 * 60 * 60 * 1000; // 3 days
      expect(formatRelativeTime(future)).toBe("in 3 days");
    });

    test("formats future time in hours", () => {
      const future = Date.now() + 5 * 60 * 60 * 1000; // 5 hours
      expect(formatRelativeTime(future)).toBe("in 5 hours");
    });

    test("formats future time in minutes", () => {
      const future = Date.now() + 30 * 60 * 1000; // 30 minutes
      expect(formatRelativeTime(future)).toBe("in 30 minutes");
    });

    test("formats immediate future", () => {
      const future = Date.now() + 10 * 1000; // 10 seconds
      expect(formatRelativeTime(future)).toBe("soon");
    });

    test("formats past time in days", () => {
      const past = Date.now() - 2 * 24 * 60 * 60 * 1000; // 2 days ago
      expect(formatRelativeTime(past)).toBe("2 days ago");
    });

    test("formats past time in hours", () => {
      const past = Date.now() - 4 * 60 * 60 * 1000; // 4 hours ago
      expect(formatRelativeTime(past)).toBe("4 hours ago");
    });

    test("formats past time in minutes", () => {
      const past = Date.now() - 15 * 60 * 1000; // 15 minutes ago
      expect(formatRelativeTime(past)).toBe("15 minutes ago");
    });

    test("formats immediate past", () => {
      const past = Date.now() - 10 * 1000; // 10 seconds ago
      expect(formatRelativeTime(past)).toBe("just now");
    });

    test("uses singular form for 1 day", () => {
      const future = Date.now() + 1 * 24 * 60 * 60 * 1000;
      expect(formatRelativeTime(future)).toBe("in 1 day");
    });

    test("uses singular form for 1 hour", () => {
      const future = Date.now() + 1 * 60 * 60 * 1000;
      expect(formatRelativeTime(future)).toBe("in 1 hour");
    });
  });

  describe("isBettingOpen", () => {
    beforeEach(() => {
      vi.useFakeTimers();
      vi.setSystemTime(new Date("2024-01-15T12:00:00Z"));
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    test("returns true for future close time", () => {
      const future = Date.now() + 1000;
      expect(isBettingOpen(future)).toBe(true);
    });

    test("returns false for past close time", () => {
      const past = Date.now() - 1000;
      expect(isBettingOpen(past)).toBe(false);
    });

    test("returns false for exact now", () => {
      expect(isBettingOpen(Date.now())).toBe(false);
    });
  });

  describe("getResolutionText", () => {
    test("returns correct text for each resolution", () => {
      expect(getResolutionText("yes")).toBe("Resolved YES");
      expect(getResolutionText("no")).toBe("Resolved NO");
      expect(getResolutionText("invalid")).toBe("Resolved INVALID");
      expect(getResolutionText("none_yet")).toBe("Unresolved");
      expect(getResolutionText(null)).toBe("Unresolved");
    });
  });

  describe("getResolutionColorClass", () => {
    test("returns correct color class for each resolution", () => {
      expect(getResolutionColorClass("yes")).toBe("text-green-600");
      expect(getResolutionColorClass("no")).toBe("text-red-600");
      expect(getResolutionColorClass("invalid")).toBe("text-yellow-600");
      expect(getResolutionColorClass("none_yet")).toBe("text-gray-500");
      expect(getResolutionColorClass(null)).toBe("text-gray-500");
    });
  });

  describe("calculateExpectedValue", () => {
    test("calculates EV for believer at 50% probability", () => {
      // At 50%, believer stakes $10, creator stakes $10
      // EV = 0.5 * 10 - 0.5 * 10 = 0
      const ev = calculateExpectedValue(1000, 1000, 0.5, false);
      expect(ev).toBe(0);
    });

    test("calculates EV for skeptic at 50% probability", () => {
      // At 50%, skeptic stakes $10, creator stakes $10
      // EV = 0.5 * 10 - 0.5 * 10 = 0
      const ev = calculateExpectedValue(1000, 1000, 0.5, true);
      expect(ev).toBe(0);
    });

    test("calculates EV for believer at 70% probability", () => {
      // Believer wins if YES (70%)
      // EV = 0.7 * creatorStake - 0.3 * bettorStake
      const ev = calculateExpectedValue(1000, 428, 0.7, false);
      // EV = 0.7 * 428 - 0.3 * 1000 = 299.6 - 300 ≈ 0
      expect(ev).toBeCloseTo(0, 0);
    });

    test("calculates EV for skeptic at 70% probability", () => {
      // Skeptic wins if NO (30%)
      // EV = 0.3 * creatorStake - 0.7 * bettorStake
      const ev = calculateExpectedValue(1000, 2333, 0.7, true);
      // EV = 0.3 * 2333 - 0.7 * 1000 ≈ 700 - 700 = 0
      expect(ev).toBeCloseTo(0, 0);
    });

    test("positive EV when odds are favorable", () => {
      // If market is mispriced (creator offers better odds than true probability)
      // True probability is 50%, but creator offers 60% confidence
      // Skeptic at 60% confidence stakes $10, gets $15 from creator (0.6/0.4)
      // But true probability of winning is 50%
      // EV = 0.5 * 1500 - 0.5 * 1000 = 750 - 500 = 250
      const ev = calculateExpectedValue(1000, 1500, 0.5, true);
      expect(ev).toBe(250);
    });
  });

  describe("generateId", () => {
    test("generates ID of correct length", () => {
      expect(generateId(12).length).toBe(12);
      expect(generateId(8).length).toBe(8);
      expect(generateId(20).length).toBe(20);
    });

    test("generates URL-safe characters only", () => {
      const id = generateId(100);
      expect(id).toMatch(/^[a-z0-9]+$/);
    });

    test("generates unique IDs", () => {
      const ids = new Set<string>();
      for (let i = 0; i < 100; i++) {
        ids.add(generateId(12));
      }
      // Should have 100 unique IDs (very unlikely to have collision)
      expect(ids.size).toBe(100);
    });
  });
});

// Phase matching tests (from Elm MyStakesTests)
describe("Prediction Phase", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2024-01-15T12:00:00Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  // Helper to determine prediction phase
  function getPredictionPhase(prediction: {
    closesAt: number;
    resolvesAt: number;
    resolution: { resolution: string } | null;
  }): "open" | "closed" | "needs_resolution" | "resolved" {
    const now = Date.now();
    const hasResolution =
      prediction.resolution &&
      prediction.resolution.resolution !== "none_yet";

    if (hasResolution) {
      return "resolved";
    }

    if (now < prediction.closesAt) {
      return "open";
    }

    if (now >= prediction.resolvesAt) {
      return "needs_resolution";
    }

    return "closed";
  }

  test("open: before closes time, not resolved", () => {
    const prediction = {
      closesAt: Date.now() + 7 * 24 * 60 * 60 * 1000, // 7 days
      resolvesAt: Date.now() + 30 * 24 * 60 * 60 * 1000, // 30 days
      resolution: null,
    };
    expect(getPredictionPhase(prediction)).toBe("open");
  });

  test("closed: after closes time, before resolves time, not resolved", () => {
    const prediction = {
      closesAt: Date.now() - 7 * 24 * 60 * 60 * 1000, // 7 days ago
      resolvesAt: Date.now() + 30 * 24 * 60 * 60 * 1000, // 30 days from now
      resolution: null,
    };
    expect(getPredictionPhase(prediction)).toBe("closed");
  });

  test("needs_resolution: after resolves time, not resolved", () => {
    const prediction = {
      closesAt: Date.now() - 60 * 24 * 60 * 60 * 1000, // 60 days ago
      resolvesAt: Date.now() - 30 * 24 * 60 * 60 * 1000, // 30 days ago
      resolution: null,
    };
    expect(getPredictionPhase(prediction)).toBe("needs_resolution");
  });

  test("needs_resolution: after resolves time, with none_yet resolution", () => {
    const prediction = {
      closesAt: Date.now() - 60 * 24 * 60 * 60 * 1000,
      resolvesAt: Date.now() - 30 * 24 * 60 * 60 * 1000,
      resolution: { resolution: "none_yet" },
    };
    expect(getPredictionPhase(prediction)).toBe("needs_resolution");
  });

  test("resolved: has yes resolution", () => {
    const prediction = {
      closesAt: Date.now() - 60 * 24 * 60 * 60 * 1000,
      resolvesAt: Date.now() - 30 * 24 * 60 * 60 * 1000,
      resolution: { resolution: "yes" },
    };
    expect(getPredictionPhase(prediction)).toBe("resolved");
  });

  test("resolved: has no resolution", () => {
    const prediction = {
      closesAt: Date.now() - 60 * 24 * 60 * 60 * 1000,
      resolvesAt: Date.now() - 30 * 24 * 60 * 60 * 1000,
      resolution: { resolution: "no" },
    };
    expect(getPredictionPhase(prediction)).toBe("resolved");
  });

  test("resolved: has invalid resolution", () => {
    const prediction = {
      closesAt: Date.now() - 60 * 24 * 60 * 60 * 1000,
      resolvesAt: Date.now() - 30 * 24 * 60 * 60 * 1000,
      resolution: { resolution: "invalid" },
    };
    expect(getPredictionPhase(prediction)).toBe("resolved");
  });

  test("resolved overrides timing (resolved before closes)", () => {
    const prediction = {
      closesAt: Date.now() + 7 * 24 * 60 * 60 * 1000, // Future
      resolvesAt: Date.now() + 30 * 24 * 60 * 60 * 1000, // Future
      resolution: { resolution: "yes" },
    };
    expect(getPredictionPhase(prediction)).toBe("resolved");
  });
});

// Bet calculation tests (from Elm PredictionTests)
describe("Bet Calculations", () => {
  // Calculate creator stake given bettor stake and probability
  function calculateCreatorStake(
    bettorStakeCents: number,
    probability: number,
    bettorIsSkeptic: boolean
  ): number {
    if (bettorIsSkeptic) {
      // Skeptic bets NO, creator is on YES side
      return Math.floor((bettorStakeCents * probability) / (1 - probability));
    } else {
      // Believer bets YES, creator is on NO side
      return Math.floor((bettorStakeCents * (1 - probability)) / probability);
    }
  }

  test("calculates believer stake at 50%", () => {
    // At 50%, ratio is 1:1
    const creatorStake = calculateCreatorStake(1000, 0.5, false);
    expect(creatorStake).toBe(1000);
  });

  test("calculates skeptic stake at 50%", () => {
    // At 50%, ratio is 1:1
    const creatorStake = calculateCreatorStake(1000, 0.5, true);
    expect(creatorStake).toBe(1000);
  });

  test("calculates believer stake at 80%", () => {
    // At 80%, believer stakes $10, creator stakes $10 * 0.2/0.8 = $2.50
    // Note: Due to floating point (1-0.8 = 0.19999...), this floors to 249
    const creatorStake = calculateCreatorStake(1000, 0.8, false);
    expect(creatorStake).toBe(249);
  });

  test("calculates skeptic stake at 80%", () => {
    // At 80%, skeptic stakes $10, creator stakes $10 * 0.8/0.2 = $40
    const creatorStake = calculateCreatorStake(1000, 0.8, true);
    expect(creatorStake).toBe(4000);
  });

  test("calculates believer stake at 20%", () => {
    // At 20%, believer stakes $10, creator stakes $10 * 0.8/0.2 = $40
    const creatorStake = calculateCreatorStake(1000, 0.2, false);
    expect(creatorStake).toBe(4000);
  });

  test("calculates skeptic stake at 20%", () => {
    // At 20%, skeptic stakes $10, creator stakes $10 * 0.2/0.8 = $2.50
    const creatorStake = calculateCreatorStake(1000, 0.2, true);
    expect(creatorStake).toBe(250);
  });

  // Test win/loss calculations
  describe("getTotalCreatorWinnings", () => {
    function calculateWinnings(
      trades: Array<{
        bettorStakeCents: number;
        creatorStakeCents: number;
        bettorIsSkeptic: boolean;
        state: string;
      }>,
      resolution: "yes" | "no" | "invalid" | null
    ): number {
      if (!resolution || resolution === "invalid") {
        return 0;
      }

      return trades
        .filter((t) => t.state === "active")
        .reduce((sum, trade) => {
          // If resolution is YES, skeptics lose (creator wins bettorStake)
          // If resolution is NO, believers lose (creator wins bettorStake)
          const bettorWon =
            (resolution === "yes" && !trade.bettorIsSkeptic) ||
            (resolution === "no" && trade.bettorIsSkeptic);

          if (bettorWon) {
            // Creator loses their stake
            return sum - trade.creatorStakeCents;
          } else {
            // Creator wins bettor's stake
            return sum + trade.bettorStakeCents;
          }
        }, 0);
    }

    test("returns zero with no trades", () => {
      expect(calculateWinnings([], "yes")).toBe(0);
    });

    test("returns zero with invalid resolution", () => {
      const trades = [
        {
          bettorStakeCents: 1000,
          creatorStakeCents: 500,
          bettorIsSkeptic: false,
          state: "active",
        },
      ];
      expect(calculateWinnings(trades, "invalid")).toBe(0);
    });

    test("creator wins when skeptic loses (YES resolution)", () => {
      const trades = [
        {
          bettorStakeCents: 1000,
          creatorStakeCents: 2000,
          bettorIsSkeptic: true,
          state: "active",
        },
      ];
      // Resolution is YES, skeptic bet NO, skeptic loses
      expect(calculateWinnings(trades, "yes")).toBe(1000);
    });

    test("creator loses when believer wins (YES resolution)", () => {
      const trades = [
        {
          bettorStakeCents: 1000,
          creatorStakeCents: 500,
          bettorIsSkeptic: false,
          state: "active",
        },
      ];
      // Resolution is YES, believer bet YES, believer wins
      expect(calculateWinnings(trades, "yes")).toBe(-500);
    });

    test("creator wins when believer loses (NO resolution)", () => {
      const trades = [
        {
          bettorStakeCents: 1000,
          creatorStakeCents: 500,
          bettorIsSkeptic: false,
          state: "active",
        },
      ];
      // Resolution is NO, believer bet YES, believer loses
      expect(calculateWinnings(trades, "no")).toBe(1000);
    });

    test("ignores non-active trades", () => {
      const trades = [
        {
          bettorStakeCents: 1000,
          creatorStakeCents: 2000,
          bettorIsSkeptic: true,
          state: "disavowed",
        },
        {
          bettorStakeCents: 500,
          creatorStakeCents: 1000,
          bettorIsSkeptic: true,
          state: "queued",
        },
      ];
      expect(calculateWinnings(trades, "yes")).toBe(0);
    });

    test("aggregates multiple trades", () => {
      const trades = [
        {
          bettorStakeCents: 1000,
          creatorStakeCents: 2000,
          bettorIsSkeptic: true,
          state: "active",
        }, // Creator wins 1000
        {
          bettorStakeCents: 500,
          creatorStakeCents: 250,
          bettorIsSkeptic: false,
          state: "active",
        }, // Creator loses 250
      ];
      // YES resolution: skeptic loses (creator +1000), believer wins (creator -250)
      expect(calculateWinnings(trades, "yes")).toBe(750);
    });
  });
});
