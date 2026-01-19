import { convexTest } from "convex-test";
import { expect, test, describe, vi } from "vitest";
import { api } from "./_generated/api";
import { modules, schema } from "./testHelpers";
import { Id } from "./_generated/dataModel";

// Helper to create a user directly in the database and return authenticated context
async function setupAuthenticatedUser(
  t: ReturnType<typeof convexTest>,
  userData: { username: string; email: string }
) {
  // Create user directly in database
  // Note: _creationTime is set automatically by Convex
  const userId = await t.run(async (ctx) => {
    return await ctx.db.insert("users", {
      username: userData.username,
      email: userData.email,
    });
  });

  // Return authenticated context using withIdentity
  // The subject format for @convex-dev/auth is "userId|sessionId"
  const authedT = t.withIdentity({ subject: `${userId}|test-session` });

  return { userId, t: authedT };
}

describe("Predictions", () => {
  describe("create", () => {
    test("creates prediction with valid inputs", async () => {
      const t = convexTest(schema, modules);
      const { t: authedT, userId } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const now = Date.now();
      const result = await authedT.mutation(api.predictions.create, {
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
      const t = convexTest(schema, modules);
      const now = Date.now();

      await expect(
        t.mutation(api.predictions.create, {
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
      const t = convexTest(schema, modules);
      const { t: authedT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const now = Date.now();

      // Low > High
      await expect(
        authedT.mutation(api.predictions.create, {
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
      const t = convexTest(schema, modules);
      const { t: authedT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const now = Date.now();

      await expect(
        authedT.mutation(api.predictions.create, {
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
      const t = convexTest(schema, modules);
      const { t: authedT, userId } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const now = Date.now();
      const result = await authedT.mutation(api.predictions.create, {
        prediction: "Test prediction",
        certaintyLowP: 0.5,
        certaintyHighP: 0.7,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      // Check that the user is following the prediction
      const follows = await t.run(async (ctx) => {
        return await ctx.db
          .query("predictionFollows")
          .withIndex("by_follower", (q) => q.eq("followerId", userId))
          .collect();
      });

      expect(follows.length).toBe(1);
      expect(follows[0].predictionId).toBe(result.id);
    });

    test("stores special rules", async () => {
      const t = convexTest(schema, modules);
      const { t: authedT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const now = Date.now();
      const result = await authedT.mutation(api.predictions.create, {
        prediction: "Test prediction",
        certaintyLowP: 0.5,
        certaintyHighP: 0.7,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        specialRules: "Must be confirmed by two sources",
        viewPrivacy: "public",
      });

      const prediction = await t.run(async (ctx) => {
        return await ctx.db.get(result.id);
      });

      expect(prediction?.specialRules).toBe("Must be confirmed by two sources");
    });
  });

  describe("getByPredictionId", () => {
    test("returns prediction with all fields", async () => {
      const t = convexTest(schema, modules);
      const { t: authedT, userId } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const now = Date.now();
      const createResult = await authedT.mutation(api.predictions.create, {
        prediction: "Test prediction",
        certaintyLowP: 0.3,
        certaintyHighP: 0.5,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      const result = await t.query(api.predictions.getByPredictionId, {
        predictionId: createResult.predictionId,
      });

      expect(result).not.toBeNull();
      expect(result?.prediction).toBe("Test prediction");
      expect(result?.certaintyLowP).toBe(0.3);
      expect(result?.certaintyHighP).toBe(0.5);
      expect(result?.maximumStakeCents).toBe(10000);
      expect(result?.creatorUsername).toBe("alice");
    });

    test("returns null for nonexistent prediction", async () => {
      const t = convexTest(schema, modules);

      const result = await t.query(api.predictions.getByPredictionId, {
        predictionId: "nonexistent123",
      });

      expect(result).toBeNull();
    });
  });

  describe("resolve", () => {
    test("creator can resolve prediction", async () => {
      const t = convexTest(schema, modules);
      const { t: authedT, userId } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const now = Date.now();
      const createResult = await authedT.mutation(api.predictions.create, {
        prediction: "Test prediction",
        certaintyLowP: 0.5,
        certaintyHighP: 0.7,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      await authedT.mutation(api.predictions.resolve, {
        predictionId: createResult.predictionId,
        resolution: "yes",
        notes: "It happened!",
      });

      const prediction = await t.query(api.predictions.getByPredictionId, {
        predictionId: createResult.predictionId,
      });

      expect(prediction?.resolution?.resolution).toBe("yes");
      expect(prediction?.resolution?.notes).toBe("It happened!");
    });

    test("non-creator cannot resolve", async () => {
      const t = convexTest(schema, modules);

      // Create prediction as alice
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const now = Date.now();
      const createResult = await aliceT.mutation(api.predictions.create, {
        prediction: "Test prediction",
        certaintyLowP: 0.5,
        certaintyHighP: 0.7,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      // Try to resolve as bob
      const { t: bobT } = await setupAuthenticatedUser(t, {
        username: "bob",
        email: "bob@example.com",
      });

      await expect(
        bobT.mutation(api.predictions.resolve, {
          predictionId: createResult.predictionId,
          resolution: "yes",
        })
      ).rejects.toThrow("Only the creator can resolve");
    });

    test("can resolve as invalid", async () => {
      const t = convexTest(schema, modules);
      const { t: authedT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const now = Date.now();
      const createResult = await authedT.mutation(api.predictions.create, {
        prediction: "Test prediction",
        certaintyLowP: 0.5,
        certaintyHighP: 0.7,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      await authedT.mutation(api.predictions.resolve, {
        predictionId: createResult.predictionId,
        resolution: "invalid",
        notes: "Poorly worded prediction",
      });

      const prediction = await t.query(api.predictions.getByPredictionId, {
        predictionId: createResult.predictionId,
      });

      expect(prediction?.resolution?.resolution).toBe("invalid");
    });
  });

  describe("setFollowing", () => {
    test("user can follow prediction", async () => {
      const t = convexTest(schema, modules);

      // Create prediction as alice
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const now = Date.now();
      const createResult = await aliceT.mutation(api.predictions.create, {
        prediction: "Test prediction",
        certaintyLowP: 0.5,
        certaintyHighP: 0.7,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      // Bob follows the prediction
      const { t: bobT, userId: bobId } = await setupAuthenticatedUser(t, {
        username: "bob",
        email: "bob@example.com",
      });

      await bobT.mutation(api.predictions.setFollowing, {
        predictionId: createResult.predictionId,
        following: true,
      });

      const follows = await t.run(async (ctx) => {
        return await ctx.db
          .query("predictionFollows")
          .withIndex("by_follower", (q) => q.eq("followerId", bobId))
          .collect();
      });

      expect(follows.length).toBe(1);
    });

    test("user can unfollow prediction", async () => {
      const t = convexTest(schema, modules);

      // Create prediction as alice
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const now = Date.now();
      const createResult = await aliceT.mutation(api.predictions.create, {
        prediction: "Test prediction",
        certaintyLowP: 0.5,
        certaintyHighP: 0.7,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      // Bob follows then unfollows
      const { t: bobT, userId: bobId } = await setupAuthenticatedUser(t, {
        username: "bob",
        email: "bob@example.com",
      });

      await bobT.mutation(api.predictions.setFollowing, {
        predictionId: createResult.predictionId,
        following: true,
      });

      await bobT.mutation(api.predictions.setFollowing, {
        predictionId: createResult.predictionId,
        following: false,
      });

      const follows = await t.run(async (ctx) => {
        return await ctx.db
          .query("predictionFollows")
          .withIndex("by_follower", (q) => q.eq("followerId", bobId))
          .collect();
      });

      expect(follows.length).toBe(0);
    });
  });

  describe("listPublic", () => {
    test("returns only public predictions", async () => {
      const t = convexTest(schema, modules);
      const { t: authedT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const now = Date.now();

      // Create one public and one link-only prediction
      await authedT.mutation(api.predictions.create, {
        prediction: "Public prediction",
        certaintyLowP: 0.5,
        certaintyHighP: 0.7,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "public",
      });

      await authedT.mutation(api.predictions.create, {
        prediction: "Link-only prediction",
        certaintyLowP: 0.5,
        certaintyHighP: 0.7,
        maximumStakeCents: 10000,
        closesAt: now + 7 * 24 * 60 * 60 * 1000,
        resolvesAt: now + 30 * 24 * 60 * 60 * 1000,
        viewPrivacy: "link_only",
      });

      const publicPredictions = await t.query(api.predictions.listPublic, {
        limit: 10,
      });

      expect(publicPredictions.length).toBe(1);
      expect(publicPredictions[0].prediction).toBe("Public prediction");
    });
  });
});
