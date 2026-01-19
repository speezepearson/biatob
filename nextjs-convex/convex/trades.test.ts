import { convexTest } from "convex-test";
import { expect, test, describe } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

// Helper to create a user and get token
async function createUser(
  t: ReturnType<typeof convexTest>,
  user: { username: string; email: string; password: string }
) {
  const { code } = await t.mutation(api.auth.createEmailVerification, {
    email: user.email,
  });
  await t.mutation(api.auth.verifyEmailCode, { email: user.email, code });
  const result = await t.mutation(api.auth.register, {
    username: user.username,
    email: user.email,
    password: user.password,
  });
  return result.token;
}

// Helper to create a prediction
async function createPrediction(
  t: ReturnType<typeof convexTest>,
  token: string,
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
  const result = await t.mutation(api.predictions.create, {
    token,
    prediction: options.prediction ?? "Test prediction",
    certaintyLowP: options.certaintyLowP ?? 0.6,
    certaintyHighP: options.certaintyHighP ?? 0.8,
    maximumStakeCents: options.maximumStakeCents ?? 10000,
    closesAt: options.closesAt ?? now + 7 * 24 * 60 * 60 * 1000,
    resolvesAt: options.resolvesAt ?? now + 30 * 24 * 60 * 60 * 1000,
    viewPrivacy: "public",
  });
  return result.predictionId;
}

describe("Trades", () => {
  describe("stake", () => {
    test("places bet as believer (YES)", async () => {
      const t = convexTest(schema);
      const aliceToken = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });
      const bobToken = await createUser(t, {
        username: "bob",
        email: "bob@example.com",
        password: "password123",
      });

      const predictionId = await createPrediction(t, aliceToken, {
        certaintyLowP: 0.6,
        certaintyHighP: 0.8,
      });

      const result = await t.mutation(api.trades.stake, {
        token: bobToken,
        predictionId,
        bettorIsSkeptic: false,
        bettorStakeCents: 1000,
      });

      expect(result.success).toBe(true);
      expect(result.bettorStakeCents).toBe(1000);
      // At 70% midpoint, believer stakes $10, creator stakes $10 * 0.3/0.7 ≈ $4.28
      expect(result.creatorStakeCents).toBeCloseTo(428, -1);
    });

    test("places bet as skeptic (NO)", async () => {
      const t = convexTest(schema);
      const aliceToken = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });
      const bobToken = await createUser(t, {
        username: "bob",
        email: "bob@example.com",
        password: "password123",
      });

      const predictionId = await createPrediction(t, aliceToken, {
        certaintyLowP: 0.6,
        certaintyHighP: 0.8,
      });

      const result = await t.mutation(api.trades.stake, {
        token: bobToken,
        predictionId,
        bettorIsSkeptic: true,
        bettorStakeCents: 1000,
      });

      expect(result.success).toBe(true);
      expect(result.bettorStakeCents).toBe(1000);
      // At 70% midpoint, skeptic stakes $10, creator stakes $10 * 0.7/0.3 ≈ $23.33
      expect(result.creatorStakeCents).toBeCloseTo(2333, -1);
    });

    test("rejects unauthenticated request", async () => {
      const t = convexTest(schema);
      const aliceToken = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });

      const predictionId = await createPrediction(t, aliceToken);

      await expect(
        t.mutation(api.trades.stake, {
          token: "invalid",
          predictionId,
          bettorIsSkeptic: false,
          bettorStakeCents: 1000,
        })
      ).rejects.toThrow("Not authenticated");
    });

    test("rejects betting on own prediction", async () => {
      const t = convexTest(schema);
      const aliceToken = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });

      const predictionId = await createPrediction(t, aliceToken);

      await expect(
        t.mutation(api.trades.stake, {
          token: aliceToken,
          predictionId,
          bettorIsSkeptic: false,
          bettorStakeCents: 1000,
        })
      ).rejects.toThrow("You cannot bet on your own prediction");
    });

    test("rejects zero or negative stake", async () => {
      const t = convexTest(schema);
      const aliceToken = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });
      const bobToken = await createUser(t, {
        username: "bob",
        email: "bob@example.com",
        password: "password123",
      });

      const predictionId = await createPrediction(t, aliceToken);

      await expect(
        t.mutation(api.trades.stake, {
          token: bobToken,
          predictionId,
          bettorIsSkeptic: false,
          bettorStakeCents: 0,
        })
      ).rejects.toThrow("Stake must be positive");

      await expect(
        t.mutation(api.trades.stake, {
          token: bobToken,
          predictionId,
          bettorIsSkeptic: false,
          bettorStakeCents: -100,
        })
      ).rejects.toThrow("Stake must be positive");
    });

    test("rejects stake exceeding maximum", async () => {
      const t = convexTest(schema);
      const aliceToken = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });
      const bobToken = await createUser(t, {
        username: "bob",
        email: "bob@example.com",
        password: "password123",
      });

      // Create prediction with small max stake
      const predictionId = await createPrediction(t, aliceToken, {
        maximumStakeCents: 1000, // $10 max creator exposure
        certaintyLowP: 0.5,
        certaintyHighP: 0.5,
      });

      // At 50%, bettor stake = creator stake
      // Try to stake more than max
      await expect(
        t.mutation(api.trades.stake, {
          token: bobToken,
          predictionId,
          bettorIsSkeptic: false,
          bettorStakeCents: 2000, // Would require $20 from creator
        })
      ).rejects.toThrow("Exceeds maximum stake");
    });

    test("tracks remaining capacity per side", async () => {
      const t = convexTest(schema);
      const aliceToken = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });
      const bobToken = await createUser(t, {
        username: "bob",
        email: "bob@example.com",
        password: "password123",
      });
      const charlieToken = await createUser(t, {
        username: "charlie",
        email: "charlie@example.com",
        password: "password123",
      });

      const predictionId = await createPrediction(t, aliceToken, {
        maximumStakeCents: 2000, // $20 max per side
        certaintyLowP: 0.5,
        certaintyHighP: 0.5,
      });

      // Bob bets YES, using $15 of creator's capacity on believer side
      await t.mutation(api.trades.stake, {
        token: bobToken,
        predictionId,
        bettorIsSkeptic: false,
        bettorStakeCents: 1500,
      });

      // Charlie bets NO, using $15 of creator's capacity on skeptic side
      // This should work because it's a different side
      const result = await t.mutation(api.trades.stake, {
        token: charlieToken,
        predictionId,
        bettorIsSkeptic: true,
        bettorStakeCents: 1500,
      });

      expect(result.success).toBe(true);

      // Check prediction state
      const prediction = await t.query(api.predictions.getByPredictionId, {
        predictionId,
        token: aliceToken,
      });

      expect(prediction?.believerStakes).toBe(1500);
      expect(prediction?.skepticStakes).toBe(1500);
      expect(prediction?.remainingBelieverStakes).toBe(500);
      expect(prediction?.remainingSkepticStakes).toBe(500);
    });

    test("auto-follows prediction after betting", async () => {
      const t = convexTest(schema);
      const aliceToken = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });
      const bobToken = await createUser(t, {
        username: "bob",
        email: "bob@example.com",
        password: "password123",
      });

      const predictionId = await createPrediction(t, aliceToken);

      // Bob is not following initially
      const beforeBet = await t.query(api.predictions.getByPredictionId, {
        predictionId,
        token: bobToken,
      });
      expect(beforeBet?.isFollowing).toBe(false);

      // Bob places a bet
      await t.mutation(api.trades.stake, {
        token: bobToken,
        predictionId,
        bettorIsSkeptic: false,
        bettorStakeCents: 1000,
      });

      // Bob should now be following
      const afterBet = await t.query(api.predictions.getByPredictionId, {
        predictionId,
        token: bobToken,
      });
      expect(afterBet?.isFollowing).toBe(true);
    });

    test("stores notes with trade", async () => {
      const t = convexTest(schema);
      const aliceToken = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });
      const bobToken = await createUser(t, {
        username: "bob",
        email: "bob@example.com",
        password: "password123",
      });

      const predictionId = await createPrediction(t, aliceToken);

      await t.mutation(api.trades.stake, {
        token: bobToken,
        predictionId,
        bettorIsSkeptic: false,
        bettorStakeCents: 1000,
        notes: "I think this will definitely happen",
      });

      const prediction = await t.query(api.predictions.getByPredictionId, {
        predictionId,
        token: aliceToken,
      });

      expect(prediction?.trades[0].notes).toBe("I think this will definitely happen");
    });

    test("calculates correct odds for different probabilities", async () => {
      const t = convexTest(schema);
      const aliceToken = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });
      const bobToken = await createUser(t, {
        username: "bob",
        email: "bob@example.com",
        password: "password123",
      });

      // High confidence (90%)
      const highConfPrediction = await createPrediction(t, aliceToken, {
        certaintyLowP: 0.85,
        certaintyHighP: 0.95,
      });

      // Skeptic at 90% confidence: skeptic stakes $10, creator stakes $10 * 0.9/0.1 = $90
      const highResult = await t.mutation(api.trades.stake, {
        token: bobToken,
        predictionId: highConfPrediction,
        bettorIsSkeptic: true,
        bettorStakeCents: 1000,
      });
      expect(highResult.creatorStakeCents).toBeCloseTo(9000, -2);

      // Low confidence (20%)
      const lowConfPrediction = await createPrediction(t, aliceToken, {
        prediction: "Low confidence prediction",
        certaintyLowP: 0.15,
        certaintyHighP: 0.25,
      });

      // Believer at 20% confidence: believer stakes $10, creator stakes $10 * 0.8/0.2 = $40
      const lowResult = await t.mutation(api.trades.stake, {
        token: bobToken,
        predictionId: lowConfPrediction,
        bettorIsSkeptic: false,
        bettorStakeCents: 1000,
      });
      expect(lowResult.creatorStakeCents).toBeCloseTo(4000, -2);
    });
  });

  describe("disavow", () => {
    test("bettor can disavow their trade", async () => {
      const t = convexTest(schema);
      const aliceToken = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });
      const bobToken = await createUser(t, {
        username: "bob",
        email: "bob@example.com",
        password: "password123",
      });

      const predictionId = await createPrediction(t, aliceToken);

      await t.mutation(api.trades.stake, {
        token: bobToken,
        predictionId,
        bettorIsSkeptic: false,
        bettorStakeCents: 1000,
      });

      // Get the trade ID
      const prediction = await t.query(api.predictions.getByPredictionId, {
        predictionId,
        token: bobToken,
      });
      const tradeId = prediction!.trades[0]._id;

      // Disavow
      const result = await t.mutation(api.trades.disavow, {
        token: bobToken,
        tradeId,
      });

      expect(result.success).toBe(true);

      // Check trade state
      const updatedPrediction = await t.query(api.predictions.getByPredictionId, {
        predictionId,
        token: aliceToken,
      });
      expect(updatedPrediction?.trades[0].state).toBe("disavowed");
    });

    test("non-bettor cannot disavow trade", async () => {
      const t = convexTest(schema);
      const aliceToken = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });
      const bobToken = await createUser(t, {
        username: "bob",
        email: "bob@example.com",
        password: "password123",
      });
      const charlieToken = await createUser(t, {
        username: "charlie",
        email: "charlie@example.com",
        password: "password123",
      });

      const predictionId = await createPrediction(t, aliceToken);

      await t.mutation(api.trades.stake, {
        token: bobToken,
        predictionId,
        bettorIsSkeptic: false,
        bettorStakeCents: 1000,
      });

      const prediction = await t.query(api.predictions.getByPredictionId, {
        predictionId,
        token: bobToken,
      });
      const tradeId = prediction!.trades[0]._id;

      // Charlie tries to disavow Bob's trade
      await expect(
        t.mutation(api.trades.disavow, {
          token: charlieToken,
          tradeId,
        })
      ).rejects.toThrow("You can only disavow your own trades");
    });

    test("disavowed trade doesn't count toward exposure", async () => {
      const t = convexTest(schema);
      const aliceToken = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });
      const bobToken = await createUser(t, {
        username: "bob",
        email: "bob@example.com",
        password: "password123",
      });

      const predictionId = await createPrediction(t, aliceToken, {
        maximumStakeCents: 2000,
        certaintyLowP: 0.5,
        certaintyHighP: 0.5,
      });

      // Bob bets $15
      await t.mutation(api.trades.stake, {
        token: bobToken,
        predictionId,
        bettorIsSkeptic: false,
        bettorStakeCents: 1500,
      });

      // Get trade and disavow
      const prediction = await t.query(api.predictions.getByPredictionId, {
        predictionId,
        token: bobToken,
      });
      const tradeId = prediction!.trades[0]._id;
      await t.mutation(api.trades.disavow, { token: bobToken, tradeId });

      // Now Bob should be able to bet the full amount again
      const result = await t.mutation(api.trades.stake, {
        token: bobToken,
        predictionId,
        bettorIsSkeptic: false,
        bettorStakeCents: 2000,
      });

      expect(result.success).toBe(true);
    });
  });

  describe("getMyTrades", () => {
    test("returns user's trades", async () => {
      const t = convexTest(schema);
      const aliceToken = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });
      const bobToken = await createUser(t, {
        username: "bob",
        email: "bob@example.com",
        password: "password123",
      });

      const predictionId = await createPrediction(t, aliceToken);

      await t.mutation(api.trades.stake, {
        token: bobToken,
        predictionId,
        bettorIsSkeptic: false,
        bettorStakeCents: 1000,
      });

      const trades = await t.query(api.trades.getMyTrades, { token: bobToken });

      expect(trades.length).toBe(1);
      expect(trades[0].bettorStakeCents).toBe(1000);
      expect(trades[0].prediction?.prediction).toBe("Test prediction");
    });

    test("rejects unauthenticated request", async () => {
      const t = convexTest(schema);

      await expect(
        t.query(api.trades.getMyTrades, { token: "invalid" })
      ).rejects.toThrow("Not authenticated");
    });
  });
});
