import { convexTest } from "convex-test";
import { expect, test, describe } from "vitest";
import { api } from "./_generated/api";
import { modules, schema } from "./testHelpers";

// Helper to create a user directly in the database and return authenticated context
async function setupAuthenticatedUser(
  t: ReturnType<typeof convexTest>,
  userData: { username: string; email: string }
) {
  const userId = await t.run(async (ctx) => {
    return await ctx.db.insert("users", {
      username: userData.username,
      email: userData.email,
      createdAt: Date.now(),
    });
  });

  const authedT = t.withIdentity({ subject: `${userId}|test-session` });
  return { userId, t: authedT };
}

// Helper to create a prediction
async function createPrediction(
  authedT: ReturnType<typeof convexTest>,
  options: {
    prediction?: string;
    certaintyLowP?: number;
    certaintyHighP?: number;
    maximumStakeCents?: number;
    closesAt?: number;
    resolvesAt?: number;
  } = {}
) {
  const now = Date.now();
  return await authedT.mutation(api.predictions.create, {
    prediction: options.prediction ?? "Test prediction",
    certaintyLowP: options.certaintyLowP ?? 0.6,
    certaintyHighP: options.certaintyHighP ?? 0.8,
    maximumStakeCents: options.maximumStakeCents ?? 10000,
    closesAt: options.closesAt ?? now + 7 * 24 * 60 * 60 * 1000,
    resolvesAt: options.resolvesAt ?? now + 30 * 24 * 60 * 60 * 1000,
    viewPrivacy: "public",
  });
}

describe("Trades", () => {
  describe("stake", () => {
    test("places bet as believer (YES)", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });
      const { t: bobT, userId: bobId } = await setupAuthenticatedUser(t, {
        username: "bob",
        email: "bob@example.com",
      });

      const prediction = await createPrediction(aliceT);

      const result = await bobT.mutation(api.trades.stake, {
        predictionId: prediction.predictionId,
        bettorIsSkeptic: false, // believer
        bettorStakeCents: 1000,
      });

      expect(result.success).toBe(true);
      expect(result.bettorStakeCents).toBe(1000);
      expect(result.creatorStakeCents).toBeGreaterThan(0);

      // Verify the trade was created
      const trades = await t.run(async (ctx) => {
        return await ctx.db
          .query("trades")
          .withIndex("by_bettor", (q) => q.eq("bettorId", bobId))
          .collect();
      });

      expect(trades.length).toBe(1);
      expect(trades[0].bettorIsSkeptic).toBe(false);
      expect(trades[0].bettorStakeCents).toBe(1000);
      expect(trades[0].state).toBe("active");
    });

    test("places bet as skeptic (NO)", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });
      const { t: bobT, userId: bobId } = await setupAuthenticatedUser(t, {
        username: "bob",
        email: "bob@example.com",
      });

      const prediction = await createPrediction(aliceT);

      const result = await bobT.mutation(api.trades.stake, {
        predictionId: prediction.predictionId,
        bettorIsSkeptic: true, // skeptic
        bettorStakeCents: 1000,
      });

      expect(result.success).toBe(true);

      const trades = await t.run(async (ctx) => {
        return await ctx.db
          .query("trades")
          .withIndex("by_bettor", (q) => q.eq("bettorId", bobId))
          .collect();
      });

      expect(trades[0].bettorIsSkeptic).toBe(true);
    });

    test("rejects unauthenticated request", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const prediction = await createPrediction(aliceT);

      await expect(
        t.mutation(api.trades.stake, {
          predictionId: prediction.predictionId,
          bettorIsSkeptic: false,
          bettorStakeCents: 1000,
        })
      ).rejects.toThrow("Not authenticated");
    });

    test("rejects betting on own prediction", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const prediction = await createPrediction(aliceT);

      await expect(
        aliceT.mutation(api.trades.stake, {
          predictionId: prediction.predictionId,
          bettorIsSkeptic: false,
          bettorStakeCents: 1000,
        })
      ).rejects.toThrow("You cannot bet on your own prediction");
    });

    test("rejects zero or negative stake", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });
      const { t: bobT } = await setupAuthenticatedUser(t, {
        username: "bob",
        email: "bob@example.com",
      });

      const prediction = await createPrediction(aliceT);

      await expect(
        bobT.mutation(api.trades.stake, {
          predictionId: prediction.predictionId,
          bettorIsSkeptic: false,
          bettorStakeCents: 0,
        })
      ).rejects.toThrow("Stake must be positive");

      await expect(
        bobT.mutation(api.trades.stake, {
          predictionId: prediction.predictionId,
          bettorIsSkeptic: false,
          bettorStakeCents: -100,
        })
      ).rejects.toThrow("Stake must be positive");
    });

    test("rejects stake exceeding maximum", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });
      const { t: bobT } = await setupAuthenticatedUser(t, {
        username: "bob",
        email: "bob@example.com",
      });

      const prediction = await createPrediction(aliceT, {
        maximumStakeCents: 1000, // Small max
      });

      // Try to stake way more than the max allows for creator exposure
      await expect(
        bobT.mutation(api.trades.stake, {
          predictionId: prediction.predictionId,
          bettorIsSkeptic: false,
          bettorStakeCents: 100000, // Way over limit
        })
      ).rejects.toThrow("Exceeds maximum stake");
    });

    test("auto-follows prediction after betting", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });
      const { t: bobT, userId: bobId } = await setupAuthenticatedUser(t, {
        username: "bob",
        email: "bob@example.com",
      });

      const prediction = await createPrediction(aliceT);

      await bobT.mutation(api.trades.stake, {
        predictionId: prediction.predictionId,
        bettorIsSkeptic: false,
        bettorStakeCents: 1000,
      });

      const follows = await t.run(async (ctx) => {
        return await ctx.db
          .query("predictionFollows")
          .withIndex("by_follower", (q) => q.eq("followerId", bobId))
          .collect();
      });

      expect(follows.length).toBe(1);
    });

    test("stores notes with trade", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });
      const { t: bobT, userId: bobId } = await setupAuthenticatedUser(t, {
        username: "bob",
        email: "bob@example.com",
      });

      const prediction = await createPrediction(aliceT);

      await bobT.mutation(api.trades.stake, {
        predictionId: prediction.predictionId,
        bettorIsSkeptic: false,
        bettorStakeCents: 1000,
        notes: "I think this will definitely happen",
      });

      const trades = await t.run(async (ctx) => {
        return await ctx.db
          .query("trades")
          .withIndex("by_bettor", (q) => q.eq("bettorId", bobId))
          .collect();
      });

      expect(trades[0].notes).toBe("I think this will definitely happen");
    });
  });

  describe("disavow", () => {
    test("bettor can disavow their trade", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });
      const { t: bobT, userId: bobId } = await setupAuthenticatedUser(t, {
        username: "bob",
        email: "bob@example.com",
      });

      const prediction = await createPrediction(aliceT);

      await bobT.mutation(api.trades.stake, {
        predictionId: prediction.predictionId,
        bettorIsSkeptic: false,
        bettorStakeCents: 1000,
      });

      // Get the trade ID from the database
      const trades = await t.run(async (ctx) => {
        return await ctx.db
          .query("trades")
          .withIndex("by_bettor", (q) => q.eq("bettorId", bobId))
          .collect();
      });
      const tradeId = trades[0]._id;

      await bobT.mutation(api.trades.disavow, {
        tradeId,
      });

      const trade = await t.run(async (ctx) => {
        return await ctx.db.get(tradeId);
      });

      expect(trade?.state).toBe("disavowed");
    });

    test("non-bettor cannot disavow trade", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });
      const { t: bobT, userId: bobId } = await setupAuthenticatedUser(t, {
        username: "bob",
        email: "bob@example.com",
      });
      const { t: charlieT } = await setupAuthenticatedUser(t, {
        username: "charlie",
        email: "charlie@example.com",
      });

      const prediction = await createPrediction(aliceT);

      await bobT.mutation(api.trades.stake, {
        predictionId: prediction.predictionId,
        bettorIsSkeptic: false,
        bettorStakeCents: 1000,
      });

      // Get the trade ID from the database
      const trades = await t.run(async (ctx) => {
        return await ctx.db
          .query("trades")
          .withIndex("by_bettor", (q) => q.eq("bettorId", bobId))
          .collect();
      });
      const tradeId = trades[0]._id;

      // Charlie (not the bettor) tries to disavow
      await expect(
        charlieT.mutation(api.trades.disavow, {
          tradeId,
        })
      ).rejects.toThrow("You can only disavow your own trades");
    });
  });

  describe("getMyTrades", () => {
    test("returns user's trades", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });
      const { t: bobT } = await setupAuthenticatedUser(t, {
        username: "bob",
        email: "bob@example.com",
      });

      const prediction = await createPrediction(aliceT);

      await bobT.mutation(api.trades.stake, {
        predictionId: prediction.predictionId,
        bettorIsSkeptic: false,
        bettorStakeCents: 1000,
      });

      await bobT.mutation(api.trades.stake, {
        predictionId: prediction.predictionId,
        bettorIsSkeptic: true,
        bettorStakeCents: 500,
      });

      const myTrades = await bobT.query(api.trades.getMyTrades, {});

      expect(myTrades.length).toBe(2);
    });

    test("rejects unauthenticated request", async () => {
      const t = convexTest(schema, modules);

      await expect(t.query(api.trades.getMyTrades, {})).rejects.toThrow(
        "Not authenticated"
      );
    });
  });
});
