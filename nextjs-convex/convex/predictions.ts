import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { Id } from "./_generated/dataModel";
import { auth } from "./auth";
import { getCreationTime } from "./helpers";

// Generate a cryptographically secure random prediction ID (lowercase alphanumeric only)
function generatePredictionId(): string {
  const chars = "abcdefghijklmnopqrstuvwxyz0123456789";
  const randomBytes = new Uint8Array(12);
  crypto.getRandomValues(randomBytes);
  let result = "";
  for (let i = 0; i < 12; i++) {
    result += chars[randomBytes[i] % chars.length];
  }
  return result;
}

// Create a new prediction
export const create = mutation({
  args: {
    prediction: v.string(),
    certaintyLowP: v.number(),
    certaintyHighP: v.number(),
    maximumStakeCents: v.number(),
    closesAt: v.number(),
    resolvesAt: v.number(),
    specialRules: v.optional(v.string()),
    viewPrivacy: v.union(v.literal("public"), v.literal("link_only")),
  },
  handler: async (ctx, args) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) {
      throw new Error("Not authenticated");
    }

    // Validate inputs
    if (args.certaintyLowP < 0 || args.certaintyLowP > 1) {
      throw new Error("certaintyLowP must be between 0 and 1");
    }
    if (args.certaintyHighP < 0 || args.certaintyHighP > 1) {
      throw new Error("certaintyHighP must be between 0 and 1");
    }
    if (args.certaintyLowP > args.certaintyHighP) {
      throw new Error("certaintyLowP must be less than or equal to certaintyHighP");
    }
    if (args.maximumStakeCents < 0) {
      throw new Error("maximumStakeCents must be non-negative");
    }
    if (args.prediction.length < 1 || args.prediction.length > 1024) {
      throw new Error("Prediction must be 1-1024 characters");
    }

    const predictionId = generatePredictionId();

    // Note: _creationTime is set automatically by Convex; creationTimeOverride is only for migration
    const id = await ctx.db.insert("predictions", {
      predictionId,
      prediction: args.prediction,
      certaintyLowP: args.certaintyLowP,
      certaintyHighP: args.certaintyHighP,
      maximumStakeCents: args.maximumStakeCents,
      closesAt: args.closesAt,
      resolvesAt: args.resolvesAt,
      specialRules: args.specialRules,
      creatorId: userId,
      resolutionReminderSent: false,
      viewPrivacy: args.viewPrivacy,
    });

    // Auto-follow the prediction
    await ctx.db.insert("predictionFollows", {
      predictionId: id,
      followerId: userId,
    });

    return { predictionId, id };
  },
});

// Get a prediction by its human-readable ID
export const getByPredictionId = query({
  args: {
    predictionId: v.string(),
  },
  handler: async (ctx, args) => {
    const prediction = await ctx.db
      .query("predictions")
      .withIndex("by_predictionId", (q) => q.eq("predictionId", args.predictionId))
      .first();

    if (!prediction) {
      return null;
    }

    const creator = await ctx.db.get(prediction.creatorId);

    // Get the latest resolution
    const resolutions = await ctx.db
      .query("resolutions")
      .withIndex("by_prediction", (q) => q.eq("predictionId", prediction._id))
      .order("desc")
      .take(1);
    const resolution = resolutions[0] || null;

    // Get all trades
    const trades = await ctx.db
      .query("trades")
      .withIndex("by_prediction", (q) => q.eq("predictionId", prediction._id))
      .collect();

    // Enrich trades with bettor info
    const enrichedTrades = await Promise.all(
      trades.map(async (trade) => {
        const bettor = await ctx.db.get(trade.bettorId);
        return {
          ...trade,
          bettorUsername: bettor?.username || "Unknown",
        };
      })
    );

    // Check if current user is following
    let isFollowing = false;
    const currentUserId = await auth.getUserId(ctx);
    if (currentUserId) {
      const follow = await ctx.db
        .query("predictionFollows")
        .withIndex("by_prediction_and_follower", (q) =>
          q.eq("predictionId", prediction._id).eq("followerId", currentUserId)
        )
        .first();
      isFollowing = !!follow;
    }

    // Calculate stakes
    const activeTrades = enrichedTrades.filter((t) => t.state === "active");
    const believerStakes = activeTrades
      .filter((t) => !t.bettorIsSkeptic)
      .reduce((sum, t) => sum + t.bettorStakeCents, 0);
    const skepticStakes = activeTrades
      .filter((t) => t.bettorIsSkeptic)
      .reduce((sum, t) => sum + t.bettorStakeCents, 0);
    const creatorStakesForBelievers = activeTrades
      .filter((t) => !t.bettorIsSkeptic)
      .reduce((sum, t) => sum + t.creatorStakeCents, 0);
    const creatorStakesForSkeptics = activeTrades
      .filter((t) => t.bettorIsSkeptic)
      .reduce((sum, t) => sum + t.creatorStakeCents, 0);

    return {
      ...prediction,
      createdAt: getCreationTime(prediction),
      creatorUsername: creator?.username || "Unknown",
      resolution,
      trades: enrichedTrades,
      isFollowing,
      currentUserId,
      believerStakes,
      skepticStakes,
      creatorStakesForBelievers,
      creatorStakesForSkeptics,
      remainingBelieverStakes: prediction.maximumStakeCents - creatorStakesForBelievers,
      remainingSkepticStakes: prediction.maximumStakeCents - creatorStakesForSkeptics,
    };
  },
});

// Get prediction by internal ID
export const get = query({
  args: { id: v.id("predictions") },
  handler: async (ctx, args) => {
    const prediction = await ctx.db.get(args.id);
    if (!prediction) return null;
    return {
      ...prediction,
      createdAt: getCreationTime(prediction),
    };
  },
});

// List predictions created by a user
export const listByCreator = query({
  args: {
    creatorId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const predictions = await ctx.db
      .query("predictions")
      .withIndex("by_creator", (q) => q.eq("creatorId", args.creatorId))
      .order("desc")
      .collect();

    return Promise.all(
      predictions.map(async (p) => {
        const resolutions = await ctx.db
          .query("resolutions")
          .withIndex("by_prediction", (q) => q.eq("predictionId", p._id))
          .order("desc")
          .take(1);

        return {
          ...p,
          createdAt: getCreationTime(p),
          resolution: resolutions[0] || null,
        };
      })
    );
  },
});

// List all stakes (predictions created + predictions bet on) for current user
export const listMyStakes = query({
  args: {},
  handler: async (ctx) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) {
      throw new Error("Not authenticated");
    }

    // Get predictions I created
    const myPredictions = await ctx.db
      .query("predictions")
      .withIndex("by_creator", (q) => q.eq("creatorId", userId))
      .collect();

    // Get my trades
    const myTrades = await ctx.db
      .query("trades")
      .withIndex("by_bettor", (q) => q.eq("bettorId", userId))
      .collect();

    // Get unique prediction IDs from trades
    const tradedPredictionIds = [...new Set(myTrades.map((t) => t.predictionId))];

    // Get those predictions
    const tradedPredictions = await Promise.all(
      tradedPredictionIds
        .filter((id) => !myPredictions.some((p) => p._id === id))
        .map((id) => ctx.db.get(id))
    );

    // Combine and enrich
    const allPredictions = [
      ...myPredictions,
      ...tradedPredictions.filter((p) => p !== null),
    ];

    return Promise.all(
      allPredictions.map(async (p) => {
        if (!p) return null;

        const creator = await ctx.db.get(p.creatorId);

        const resolutions = await ctx.db
          .query("resolutions")
          .withIndex("by_prediction", (q) => q.eq("predictionId", p._id))
          .order("desc")
          .take(1);

        const trades = await ctx.db
          .query("trades")
          .withIndex("by_prediction", (q) => q.eq("predictionId", p._id))
          .collect();

        const myTradesForThis = trades.filter(
          (t) => t.bettorId === userId && t.state === "active"
        );

        return {
          ...p,
          createdAt: getCreationTime(p),
          creatorUsername: creator?.username || "Unknown",
          resolution: resolutions[0] || null,
          isCreator: p.creatorId === userId,
          myTrades: myTradesForThis,
        };
      })
    ).then((results) => results.filter((r) => r !== null));
  },
});

// Resolve a prediction
export const resolve = mutation({
  args: {
    predictionId: v.string(),
    resolution: v.union(
      v.literal("yes"),
      v.literal("no"),
      v.literal("invalid")
    ),
    notes: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) {
      throw new Error("Not authenticated");
    }

    const prediction = await ctx.db
      .query("predictions")
      .withIndex("by_predictionId", (q) => q.eq("predictionId", args.predictionId))
      .first();

    if (!prediction) {
      throw new Error("Prediction not found");
    }

    if (prediction.creatorId !== userId) {
      throw new Error("Only the creator can resolve this prediction");
    }

    await ctx.db.insert("resolutions", {
      predictionId: prediction._id,
      resolvedAt: Date.now(),
      resolution: args.resolution,
      notes: args.notes,
    });

    return { success: true };
  },
});

// Follow/unfollow a prediction
export const setFollowing = mutation({
  args: {
    predictionId: v.string(),
    following: v.boolean(),
  },
  handler: async (ctx, args) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) {
      throw new Error("Not authenticated");
    }

    const prediction = await ctx.db
      .query("predictions")
      .withIndex("by_predictionId", (q) => q.eq("predictionId", args.predictionId))
      .first();

    if (!prediction) {
      throw new Error("Prediction not found");
    }

    const existingFollow = await ctx.db
      .query("predictionFollows")
      .withIndex("by_prediction_and_follower", (q) =>
        q.eq("predictionId", prediction._id).eq("followerId", userId)
      )
      .first();

    if (args.following && !existingFollow) {
      await ctx.db.insert("predictionFollows", {
        predictionId: prediction._id,
        followerId: userId,
      });
    } else if (!args.following && existingFollow) {
      await ctx.db.delete(existingFollow._id);
    }

    return { success: true };
  },
});

// List public predictions (for discovery)
export const listPublic = query({
  args: {
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit || 50;

    const predictions = await ctx.db
      .query("predictions")
      .order("desc")
      .take(limit * 2); // Fetch more to filter

    const publicPredictions = predictions
      .filter((p) => p.viewPrivacy === "public")
      .slice(0, limit);

    return Promise.all(
      publicPredictions.map(async (p) => {
        const creator = await ctx.db.get(p.creatorId);

        const resolutions = await ctx.db
          .query("resolutions")
          .withIndex("by_prediction", (q) => q.eq("predictionId", p._id))
          .order("desc")
          .take(1);

        return {
          ...p,
          createdAt: getCreationTime(p),
          creatorUsername: creator?.username || "Unknown",
          resolution: resolutions[0] || null,
        };
      })
    );
  },
});
