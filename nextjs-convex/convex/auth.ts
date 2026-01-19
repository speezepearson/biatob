import { convexAuth } from "@convex-dev/auth/server";
import { Password } from "@convex-dev/auth/providers/Password";
import { query, mutation } from "./_generated/server";
import { v } from "convex/values";
import { DataModel } from "./_generated/dataModel";

// Convex Auth setup
export const { auth, signIn, signOut, store } = convexAuth({
  providers: [
    Password<DataModel>({
      profile(params) {
        return {
          email: params.email as string,
          name: params.name as string | undefined,
        };
      },
    }),
  ],
});

// Get the current user (using Convex Auth)
export const currentUser = query({
  args: {},
  handler: async (ctx) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) return null;

    const user = await ctx.db.get(userId);
    if (!user) return null;

    return {
      _id: user._id,
      username: user.username,
      email: user.email,
      name: user.name,
      createdAt: user.createdAt,
    };
  },
});

// Set username for the current user (after initial auth)
export const setUsername = mutation({
  args: { username: v.string() },
  handler: async (ctx, args) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) {
      throw new Error("Not authenticated");
    }

    const username = args.username.trim();

    // Validate username
    if (!/^[a-zA-Z0-9_]{3,32}$/.test(username)) {
      throw new Error(
        "Username must be 3-32 characters, alphanumeric and underscores only"
      );
    }

    // Check if username is taken
    const existingUsername = await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", username))
      .first();

    if (existingUsername && existingUsername._id !== userId) {
      throw new Error("Username already taken");
    }

    // Update user
    await ctx.db.patch(userId, {
      username,
      createdAt: Date.now(),
    });

    return { success: true };
  },
});

// Get user by ID
export const getUserById = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const user = await ctx.db.get(args.userId);
    if (!user) return null;

    return {
      _id: user._id,
      username: user.username,
      email: user.email,
      name: user.name,
      createdAt: user.createdAt,
    };
  },
});

// Legacy exports for backward compatibility (using Convex Auth internally)
// These are wrappers around Convex Auth that maintain the old API

export const getCurrentUser = query({
  args: {},
  handler: async (ctx) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) return null;

    const user = await ctx.db.get(userId);
    if (!user) return null;

    return {
      _id: user._id,
      username: user.username,
      email: user.email,
      createdAt: user.createdAt,
    };
  },
});
