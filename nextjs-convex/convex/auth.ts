import { v } from "convex/values";
import { mutation, query, action } from "./_generated/server";
import { api } from "./_generated/api";

// Generate a random string for tokens/nonces
function generateToken(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  let result = "";
  for (let i = 0; i < 64; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

// Generate a 6-digit verification code
function generateVerificationCode(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// Simple hash function for demo (in production, use proper crypto in an action)
function simpleHash(password: string, salt: string): string {
  // This is a simplified hash - in production you'd use bcrypt/scrypt via an action
  let hash = 0;
  const combined = password + salt;
  for (let i = 0; i < combined.length; i++) {
    const char = combined.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash;
  }
  return Math.abs(hash).toString(36) + salt.slice(0, 8);
}

// Check if user is authenticated by session token
export const getSession = query({
  args: { token: v.string() },
  handler: async (ctx, args) => {
    const session = await ctx.db
      .query("sessions")
      .withIndex("by_token", (q) => q.eq("token", args.token))
      .first();

    if (!session || session.expiresAt < Date.now()) {
      return null;
    }

    const user = await ctx.db.get(session.userId);
    if (!user) return null;

    return {
      userId: session.userId,
      username: user.username,
      email: user.email,
    };
  },
});

// Get current user by session token
export const getCurrentUser = query({
  args: { token: v.optional(v.string()) },
  handler: async (ctx, args) => {
    if (!args.token) return null;

    const session = await ctx.db
      .query("sessions")
      .withIndex("by_token", (q) => q.eq("token", args.token))
      .first();

    if (!session || session.expiresAt < Date.now()) {
      return null;
    }

    const user = await ctx.db.get(session.userId);
    if (!user) return null;

    return {
      _id: user._id,
      username: user.username,
      email: user.email,
      createdAt: user.createdAt,
    };
  },
});

// Create email verification
export const createEmailVerification = mutation({
  args: { email: v.string() },
  handler: async (ctx, args) => {
    const email = args.email.toLowerCase().trim();

    // Check if email is already registered
    const existingUser = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", email))
      .first();

    if (existingUser) {
      throw new Error("Email already registered");
    }

    // Delete any existing verification for this email
    const existing = await ctx.db
      .query("emailVerifications")
      .withIndex("by_email", (q) => q.eq("email", email))
      .collect();

    for (const e of existing) {
      await ctx.db.delete(e._id);
    }

    const code = generateVerificationCode();
    const now = Date.now();

    await ctx.db.insert("emailVerifications", {
      email,
      code,
      createdAt: now,
      expiresAt: now + 24 * 60 * 60 * 1000, // 24 hours
      verified: false,
    });

    return { code, email };
  },
});

// Verify email code
export const verifyEmailCode = mutation({
  args: { email: v.string(), code: v.string() },
  handler: async (ctx, args) => {
    const email = args.email.toLowerCase().trim();

    const verification = await ctx.db
      .query("emailVerifications")
      .withIndex("by_email_and_code", (q) =>
        q.eq("email", email).eq("code", args.code)
      )
      .first();

    if (!verification) {
      throw new Error("Invalid verification code");
    }

    if (verification.expiresAt < Date.now()) {
      throw new Error("Verification code expired");
    }

    await ctx.db.patch(verification._id, { verified: true });

    return { success: true };
  },
});

// Register a new user
export const register = mutation({
  args: {
    username: v.string(),
    email: v.string(),
    password: v.string(),
  },
  handler: async (ctx, args) => {
    const email = args.email.toLowerCase().trim();
    const username = args.username.trim();

    // Validate username
    if (!/^[a-zA-Z0-9_]{3,32}$/.test(username)) {
      throw new Error(
        "Username must be 3-32 characters, alphanumeric and underscores only"
      );
    }

    // Check email verification
    const verification = await ctx.db
      .query("emailVerifications")
      .withIndex("by_email", (q) => q.eq("email", email))
      .first();

    if (!verification || !verification.verified) {
      throw new Error("Email not verified");
    }

    // Check if username is taken
    const existingUsername = await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", username))
      .first();

    if (existingUsername) {
      throw new Error("Username already taken");
    }

    // Check if email is already registered
    const existingEmail = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", email))
      .first();

    if (existingEmail) {
      throw new Error("Email already registered");
    }

    // Create password hash
    const salt = generateToken().slice(0, 16);
    const hash = simpleHash(args.password, salt);

    // Create user
    const userId = await ctx.db.insert("users", {
      username,
      email,
      passwordHash: hash,
      passwordSalt: salt,
      createdAt: Date.now(),
    });

    // Create session
    const token = generateToken();
    await ctx.db.insert("sessions", {
      userId,
      token,
      createdAt: Date.now(),
      expiresAt: Date.now() + 30 * 24 * 60 * 60 * 1000, // 30 days
    });

    // Clean up verification
    await ctx.db.delete(verification._id);

    return { token, userId };
  },
});

// Login
export const login = mutation({
  args: {
    username: v.string(),
    password: v.string(),
  },
  handler: async (ctx, args) => {
    const username = args.username.trim();

    const user = await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", username))
      .first();

    if (!user) {
      throw new Error("Invalid username or password");
    }

    const hash = simpleHash(args.password, user.passwordSalt);
    if (hash !== user.passwordHash) {
      throw new Error("Invalid username or password");
    }

    // Create session
    const token = generateToken();
    await ctx.db.insert("sessions", {
      userId: user._id,
      token,
      createdAt: Date.now(),
      expiresAt: Date.now() + 30 * 24 * 60 * 60 * 1000, // 30 days
    });

    return { token, userId: user._id };
  },
});

// Logout
export const logout = mutation({
  args: { token: v.string() },
  handler: async (ctx, args) => {
    const session = await ctx.db
      .query("sessions")
      .withIndex("by_token", (q) => q.eq("token", args.token))
      .first();

    if (session) {
      await ctx.db.delete(session._id);
    }

    return { success: true };
  },
});

// Change password
export const changePassword = mutation({
  args: {
    token: v.string(),
    currentPassword: v.string(),
    newPassword: v.string(),
  },
  handler: async (ctx, args) => {
    const session = await ctx.db
      .query("sessions")
      .withIndex("by_token", (q) => q.eq("token", args.token))
      .first();

    if (!session || session.expiresAt < Date.now()) {
      throw new Error("Not authenticated");
    }

    const user = await ctx.db.get(session.userId);
    if (!user) {
      throw new Error("User not found");
    }

    // Verify current password
    const currentHash = simpleHash(args.currentPassword, user.passwordSalt);
    if (currentHash !== user.passwordHash) {
      throw new Error("Current password is incorrect");
    }

    // Update password
    const newSalt = generateToken().slice(0, 16);
    const newHash = simpleHash(args.newPassword, newSalt);

    await ctx.db.patch(user._id, {
      passwordHash: newHash,
      passwordSalt: newSalt,
    });

    return { success: true };
  },
});
