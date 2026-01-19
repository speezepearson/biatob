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

describe("Predictions", () => {
  describe("create", () => {
    test("creates prediction with valid inputs", async () => {
      const t = convexTest(schema);
      const token = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });

      const now = Date.now();
      const result = await t.mutation(api.predictions.create, {
        token,
        prediction: "Bitcoin will reach $100k by end of year",
        certaintyLowP: 0.3,
        certaintyHighP: 0.5,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      expect(result.predictionId).toBeDefined();
      expect(result.predictionId.length).toBe(12);
      expect(result.predictionId).toMatch(/^[a-z0-9]+$/);
    });

    test("rejects unauthenticated request", async () => {
      const t = convexTest(schema);
      const now = Date.now();

      await expect(
        t.mutation(api.predictions.create, {
          token: "invalidtoken",
          prediction: "Test prediction",
          certaintyLowP: 0.5,
          certaintyHighP: 0.7,
          maximumStakeCents: 10000,
          closesAt: now + 7 * 24 * 60 * 60 * 1000,
          resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
          viewPrivacy: "public",
        })
      ).rejects.toThrow("Not authenticated");
    });

    test("rejects invalid certainty range", async () => {
      const t = convexTest(schema);
      const token = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });

      const now = Date.now();

      // Low > High
      await expect(
        t.mutation(api.predictions.create, {
          token,
          prediction: "Test prediction",
          certaintyLowP: 0.8,
          certaintyHighP: 0.5,
          maximumStakeCents: 10000,
          closesAt: now + 7 * 24 * 60 * 60 * 1000,
          resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
          viewPrivacy: "public",
        })
      ).rejects.toThrow("certaintyLowP must be less than or equal to certaintyHighP");
    });

    test("rejects out of range certainty", async () => {
      const t = convexTest(schema);
      const token = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });

      const now = Date.now();

      await expect(
        t.mutation(api.predictions.create, {
          token,
          prediction: "Test prediction",
          certaintyLowP: -0.1,
          certaintyHighP: 0.5,
          maximumStakeCents: 10000,
          closesAt: now + 7 * 24 * 60 * 60 * 1000,
          resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
          viewPrivacy: "public",
        })
      ).rejects.toThrow("certaintyLowP must be between 0 and 1");
    });

    test("auto-follows prediction after creation", async () => {
      const t = convexTest(schema);
      const token = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });

      const now = Date.now();
      const result = await t.mutation(api.predictions.create, {
        token,
        prediction: "Test prediction",
        certaintyLowP: 0.5,
        certaintyHighP: 0.7,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      const prediction = await t.query(api.predictions.getByPredictionId, {
        predictionId: result.predictionId,
        token,
      });

      expect(prediction?.isFollowing).toBe(true);
    });

    test("stores special rules", async () => {
      const t = convexTest(schema);
      const token = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });

      const now = Date.now();
      const result = await t.mutation(api.predictions.create, {
        token,
        prediction: "Test prediction",
        certaintyLowP: 0.5,
        certaintyHighP: 0.7,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        specialRules: "Resolved based on official announcement",
        viewPrivacy: "public",
      });

      const prediction = await t.query(api.predictions.getByPredictionId, {
        predictionId: result.predictionId,
        token,
      });

      expect(prediction?.specialRules).toBe("Resolved based on official announcement");
    });
  });

  describe("getByPredictionId", () => {
    test("returns prediction with all fields", async () => {
      const t = convexTest(schema);
      const token = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });

      const now = Date.now();
      const { predictionId } = await t.mutation(api.predictions.create, {
        token,
        prediction: "Test prediction",
        certaintyLowP: 0.6,
        certaintyHighP: 0.8,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      const result = await t.query(api.predictions.getByPredictionId, {
        predictionId,
        token,
      });

      expect(result).not.toBeNull();
      expect(result!.prediction).toBe("Test prediction");
      expect(result!.certaintyLowP).toBe(0.6);
      expect(result!.certaintyHighP).toBe(0.8);
      expect(result!.maximumStakeCents).toBe(10000);
      expect(result!.creatorUsername).toBe("alice");
      expect(result!.resolution).toBeNull();
      expect(result!.trades).toEqual([]);
      expect(result!.believerStakes).toBe(0);
      expect(result!.skepticStakes).toBe(0);
    });

    test("returns null for nonexistent prediction", async () => {
      const t = convexTest(schema);

      const result = await t.query(api.predictions.getByPredictionId, {
        predictionId: "nonexistent",
      });

      expect(result).toBeNull();
    });

    test("shows following status for logged in user", async () => {
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

      const now = Date.now();
      const { predictionId } = await t.mutation(api.predictions.create, {
        token: aliceToken,
        prediction: "Test prediction",
        certaintyLowP: 0.6,
        certaintyHighP: 0.8,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      // Alice (creator) should be following
      const asAlice = await t.query(api.predictions.getByPredictionId, {
        predictionId,
        token: aliceToken,
      });
      expect(asAlice?.isFollowing).toBe(true);

      // Bob should not be following
      const asBob = await t.query(api.predictions.getByPredictionId, {
        predictionId,
        token: bobToken,
      });
      expect(asBob?.isFollowing).toBe(false);
    });
  });

  describe("resolve", () => {
    test("creator can resolve prediction", async () => {
      const t = convexTest(schema);
      const token = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });

      const now = Date.now();
      const { predictionId } = await t.mutation(api.predictions.create, {
        token,
        prediction: "Test prediction",
        certaintyLowP: 0.6,
        certaintyHighP: 0.8,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      const result = await t.mutation(api.predictions.resolve, {
        token,
        predictionId,
        resolution: "yes",
        notes: "It happened!",
      });

      expect(result.success).toBe(true);

      const prediction = await t.query(api.predictions.getByPredictionId, {
        predictionId,
        token,
      });

      expect(prediction?.resolution).not.toBeNull();
      expect(prediction?.resolution!.resolution).toBe("yes");
      expect(prediction?.resolution!.notes).toBe("It happened!");
    });

    test("non-creator cannot resolve", async () => {
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

      const now = Date.now();
      const { predictionId } = await t.mutation(api.predictions.create, {
        token: aliceToken,
        prediction: "Test prediction",
        certaintyLowP: 0.6,
        certaintyHighP: 0.8,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      await expect(
        t.mutation(api.predictions.resolve, {
          token: bobToken,
          predictionId,
          resolution: "yes",
        })
      ).rejects.toThrow("Only the creator can resolve this prediction");
    });

    test("can resolve as invalid", async () => {
      const t = convexTest(schema);
      const token = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });

      const now = Date.now();
      const { predictionId } = await t.mutation(api.predictions.create, {
        token,
        prediction: "Test prediction",
        certaintyLowP: 0.6,
        certaintyHighP: 0.8,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      await t.mutation(api.predictions.resolve, {
        token,
        predictionId,
        resolution: "invalid",
        notes: "The question was ambiguous",
      });

      const prediction = await t.query(api.predictions.getByPredictionId, {
        predictionId,
        token,
      });

      expect(prediction?.resolution!.resolution).toBe("invalid");
    });

    test("supports re-resolution (history)", async () => {
      const t = convexTest(schema);
      const token = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });

      const now = Date.now();
      const { predictionId } = await t.mutation(api.predictions.create, {
        token,
        prediction: "Test prediction",
        certaintyLowP: 0.6,
        certaintyHighP: 0.8,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      // First resolution
      await t.mutation(api.predictions.resolve, {
        token,
        predictionId,
        resolution: "yes",
      });

      // Re-resolve
      await t.mutation(api.predictions.resolve, {
        token,
        predictionId,
        resolution: "no",
        notes: "I was wrong",
      });

      const prediction = await t.query(api.predictions.getByPredictionId, {
        predictionId,
        token,
      });

      // Should show latest resolution
      expect(prediction?.resolution!.resolution).toBe("no");
    });
  });

  describe("setFollowing", () => {
    test("user can follow prediction", async () => {
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

      const now = Date.now();
      const { predictionId } = await t.mutation(api.predictions.create, {
        token: aliceToken,
        prediction: "Test prediction",
        certaintyLowP: 0.6,
        certaintyHighP: 0.8,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      // Bob follows
      await t.mutation(api.predictions.setFollowing, {
        token: bobToken,
        predictionId,
        following: true,
      });

      const prediction = await t.query(api.predictions.getByPredictionId, {
        predictionId,
        token: bobToken,
      });

      expect(prediction?.isFollowing).toBe(true);
    });

    test("user can unfollow prediction", async () => {
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

      const now = Date.now();
      const { predictionId } = await t.mutation(api.predictions.create, {
        token: aliceToken,
        prediction: "Test prediction",
        certaintyLowP: 0.6,
        certaintyHighP: 0.8,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      // Bob follows then unfollows
      await t.mutation(api.predictions.setFollowing, {
        token: bobToken,
        predictionId,
        following: true,
      });
      await t.mutation(api.predictions.setFollowing, {
        token: bobToken,
        predictionId,
        following: false,
      });

      const prediction = await t.query(api.predictions.getByPredictionId, {
        predictionId,
        token: bobToken,
      });

      expect(prediction?.isFollowing).toBe(false);
    });
  });

  describe("listMyStakes", () => {
    test("returns predictions created by user", async () => {
      const t = convexTest(schema);
      const token = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });

      const now = Date.now();
      await t.mutation(api.predictions.create, {
        token,
        prediction: "My first prediction",
        certaintyLowP: 0.6,
        certaintyHighP: 0.8,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });
      await t.mutation(api.predictions.create, {
        token,
        prediction: "My second prediction",
        certaintyLowP: 0.3,
        certaintyHighP: 0.5,
        maximumStakeCents: 5000,
        closesAt: now + 14 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 60 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      const stakes = await t.query(api.predictions.listMyStakes, { token });

      expect(stakes.length).toBe(2);
      expect(stakes.every((s) => s.isCreator)).toBe(true);
    });

    test("rejects unauthenticated request", async () => {
      const t = convexTest(schema);

      await expect(
        t.query(api.predictions.listMyStakes, { token: "invalid" })
      ).rejects.toThrow("Not authenticated");
    });
  });

  describe("listPublic", () => {
    test("returns only public predictions", async () => {
      const t = convexTest(schema);
      const token = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });

      const now = Date.now();
      await t.mutation(api.predictions.create, {
        token,
        prediction: "Public prediction",
        certaintyLowP: 0.6,
        certaintyHighP: 0.8,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });
      await t.mutation(api.predictions.create, {
        token,
        prediction: "Link-only prediction",
        certaintyLowP: 0.3,
        certaintyHighP: 0.5,
        maximumStakeCents: 5000,
        closesAt: now + 14 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 60 * 24 * 60 * 60 * 1000,
        viewPrivacy: "link_only",
      });

      const publicPredictions = await t.query(api.predictions.listPublic, {});

      expect(publicPredictions.length).toBe(1);
      expect(publicPredictions[0].prediction).toBe("Public prediction");
    });

    test("respects limit", async () => {
      const t = convexTest(schema);
      const token = await createUser(t, {
        username: "alice",
        email: "alice@example.com",
        password: "password123",
      });

      const now = Date.now();
      for (let i = 0; i < 5; i++) {
        await t.mutation(api.predictions.create, {
          token,
          prediction: `Prediction ${i}`,
          certaintyLowP: 0.5,
          certaintyHighP: 0.7,
          maximumStakeCents: 10000,
          closesAt: now + 7 * 24 * 60 * 60 * 1000,
          resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
          viewPrivacy: "public",
        });
      }

      const limited = await t.query(api.predictions.listPublic, { limit: 3 });

      expect(limited.length).toBe(3);
    });
  });
});
