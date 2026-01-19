import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { Id } from "./_generated/dataModel";

// Helper to get user from session
async function getUserFromSession(
  ctx: any,
  token: string | undefined
): Promise<{ _id: Id<"users">; username: string; email: string } | null> {
  if (!token) return null;

  const session = await ctx.db
    .query("sessions")
    .withIndex("by_token", (q: any) => q.eq("token", token))
    .first();

  if (!session || session.expiresAt < Date.now()) {
    return null;
  }

  const user = await ctx.db.get(session.userId);
  return user;
}

// Place a stake/bet on a prediction
export const stake = mutation({
  args: {
    token: v.string(),
    predictionId: v.string(),
    bettorIsSkeptic: v.boolean(),
    bettorStakeCents: v.number(),
    notes: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await getUserFromSession(ctx, args.token);
    if (!user) {
      throw new Error("Not authenticated");
    }

    if (args.bettorStakeCents <= 0) {
      throw new Error("Stake must be positive");
    }

    const prediction = await ctx.db
      .query("predictions")
      .withIndex("by_predictionId", (q) => q.eq("predictionId", args.predictionId))
      .first();

    if (!prediction) {
      throw new Error("Prediction not found");
    }

    // Check if betting is still open
    if (prediction.closesAt < Date.now()) {
      throw new Error("Betting is closed for this prediction");
    }

    // Check if already resolved
    const resolution = await ctx.db
      .query("resolutions")
      .withIndex("by_prediction", (q) => q.eq("predictionId", prediction._id))
      .first();

    if (resolution && resolution.resolution !== "none_yet") {
      throw new Error("This prediction has already been resolved");
    }

    // Can't bet on your own prediction
    if (prediction.creatorId === user._id) {
      throw new Error("You cannot bet on your own prediction");
    }

    // Calculate odds and creator's stake
    // If bettor is a skeptic (betting NO), they're betting against the creator's belief
    // If bettor is a believer (betting YES), they're betting with the creator's belief
    const midP = (prediction.certaintyLowP + prediction.certaintyHighP) / 2;

    let creatorStakeCents: number;
    if (args.bettorIsSkeptic) {
      // Bettor bets NO, creator is on YES side
      // Bettor wins if NO, stake ratio is p/(1-p) for creator
      creatorStakeCents = Math.floor(
        (args.bettorStakeCents * midP) / (1 - midP)
      );
    } else {
      // Bettor bets YES, creator is on NO side
      // Bettor wins if YES, stake ratio is (1-p)/p for creator
      creatorStakeCents = Math.floor(
        (args.bettorStakeCents * (1 - midP)) / midP
      );
    }

    // Check remaining capacity
    const existingTrades = await ctx.db
      .query("trades")
      .withIndex("by_prediction", (q) => q.eq("predictionId", prediction._id))
      .collect();

    const activeTrades = existingTrades.filter((t) => t.state === "active");

    // Calculate current exposure for this side
    const currentExposure = activeTrades
      .filter((t) => t.bettorIsSkeptic === args.bettorIsSkeptic)
      .reduce((sum, t) => sum + t.creatorStakeCents, 0);

    if (currentExposure + creatorStakeCents > prediction.maximumStakeCents) {
      throw new Error(
        `Exceeds maximum stake. Available: ${
          (prediction.maximumStakeCents - currentExposure) / 100
        } creator-dollars`
      );
    }

    const now = Date.now();

    await ctx.db.insert("trades", {
      predictionId: prediction._id,
      bettorId: user._id,
      transactedAt: now,
      bettorIsSkeptic: args.bettorIsSkeptic,
      bettorStakeCents: args.bettorStakeCents,
      creatorStakeCents,
      state: "active",
      updatedAt: now,
      notes: args.notes,
    });

    // Auto-follow the prediction
    const existingFollow = await ctx.db
      .query("predictionFollows")
      .withIndex("by_prediction_and_follower", (q) =>
        q.eq("predictionId", prediction._id).eq("followerId", user._id)
      )
      .first();

    if (!existingFollow) {
      await ctx.db.insert("predictionFollows", {
        predictionId: prediction._id,
        followerId: user._id,
      });
    }

    return {
      success: true,
      bettorStakeCents: args.bettorStakeCents,
      creatorStakeCents,
    };
  },
});

// Disavow a trade (back out)
export const disavow = mutation({
  args: {
    token: v.string(),
    tradeId: v.id("trades"),
  },
  handler: async (ctx, args) => {
    const user = await getUserFromSession(ctx, args.token);
    if (!user) {
      throw new Error("Not authenticated");
    }

    const trade = await ctx.db.get(args.tradeId);
    if (!trade) {
      throw new Error("Trade not found");
    }

    // Only the bettor can disavow their own trade
    if (trade.bettorId !== user._id) {
      throw new Error("You can only disavow your own trades");
    }

    if (trade.state !== "active" && trade.state !== "queued") {
      throw new Error("This trade cannot be disavowed");
    }

    await ctx.db.patch(args.tradeId, {
      state: "disavowed",
      updatedAt: Date.now(),
    });

    return { success: true };
  },
});

// Get trades for a prediction
export const getForPrediction = query({
  args: { predictionId: v.id("predictions") },
  handler: async (ctx, args) => {
    const trades = await ctx.db
      .query("trades")
      .withIndex("by_prediction", (q) => q.eq("predictionId", args.predictionId))
      .collect();

    return Promise.all(
      trades.map(async (trade) => {
        const bettor = await ctx.db.get(trade.bettorId);
        return {
          ...trade,
          bettorUsername: bettor?.username || "Unknown",
        };
      })
    );
  },
});

// Get user's trades
export const getMyTrades = query({
  args: { token: v.string() },
  handler: async (ctx, args) => {
    const user = await getUserFromSession(ctx, args.token);
    if (!user) {
      throw new Error("Not authenticated");
    }

    const trades = await ctx.db
      .query("trades")
      .withIndex("by_bettor", (q) => q.eq("bettorId", user._id))
      .collect();

    return Promise.all(
      trades.map(async (trade) => {
        const prediction = await ctx.db.get(trade.predictionId);
        return {
          ...trade,
          prediction: prediction
            ? {
                predictionId: prediction.predictionId,
                prediction: prediction.prediction,
              }
            : null,
        };
      })
    );
  },
});
