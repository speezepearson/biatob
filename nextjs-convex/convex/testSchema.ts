/**
 * Simplified schema for testing without Convex Auth dependencies.
 * This mirrors schema.ts but excludes authTables.
 */
import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  // Legacy password hashes for migration from old system
  legacyPasswordHashes: defineTable({
    email: v.string(),
    username: v.string(),
    salt: v.string(),
    scrypt: v.string(),
  })
    .index("by_email", ["email"])
    .index("by_username", ["username"]),

  // Users table - simplified for testing
  users: defineTable({
    email: v.optional(v.string()),
    emailVerificationTime: v.optional(v.number()),
    image: v.optional(v.string()),
    isAnonymous: v.optional(v.boolean()),
    name: v.optional(v.string()),
    username: v.optional(v.string()),
    createdAt: v.optional(v.number()),
    passwordHash: v.optional(v.string()), // for auth testing
  })
    .index("by_username", ["username"])
    .index("email", ["email"]),

  // Sessions for auth testing
  sessions: defineTable({
    userId: v.id("users"),
    token: v.string(),
    expiresAt: v.number(),
  })
    .index("by_token", ["token"])
    .index("by_user", ["userId"]),

  // Email verifications for auth testing
  emailVerifications: defineTable({
    email: v.string(),
    code: v.string(),
    createdAt: v.number(),
    verified: v.boolean(),
  })
    .index("by_email", ["email"]),

  // Predictions table
  predictions: defineTable({
    predictionId: v.string(),
    prediction: v.string(),
    certaintyLowP: v.number(),
    certaintyHighP: v.number(),
    maximumStakeCents: v.number(),
    createdAt: v.number(),
    closesAt: v.number(),
    resolvesAt: v.number(),
    specialRules: v.optional(v.string()),
    creatorId: v.id("users"),
    resolutionReminderSent: v.boolean(),
    viewPrivacy: v.union(v.literal("public"), v.literal("link_only")),
  })
    .index("by_predictionId", ["predictionId"])
    .index("by_creator", ["creatorId"])
    .index("by_resolvesAt", ["resolvesAt"]),

  // Trades/bets table
  trades: defineTable({
    predictionId: v.id("predictions"),
    bettorId: v.id("users"),
    transactedAt: v.number(),
    bettorIsSkeptic: v.boolean(),
    bettorStakeCents: v.number(),
    creatorStakeCents: v.number(),
    state: v.union(
      v.literal("active"),
      v.literal("queued"),
      v.literal("disavowed"),
      v.literal("dequeue_failed")
    ),
    updatedAt: v.number(),
    notes: v.optional(v.string()),
  })
    .index("by_prediction", ["predictionId"])
    .index("by_bettor", ["bettorId"])
    .index("by_prediction_and_bettor", ["predictionId", "bettorId"]),

  // Resolutions table
  resolutions: defineTable({
    predictionId: v.id("predictions"),
    resolvedAt: v.number(),
    resolution: v.union(
      v.literal("none_yet"),
      v.literal("yes"),
      v.literal("no"),
      v.literal("invalid")
    ),
    notes: v.optional(v.string()),
  })
    .index("by_prediction", ["predictionId"])
    .index("by_prediction_and_time", ["predictionId", "resolvedAt"]),

  // Prediction follows
  predictionFollows: defineTable({
    predictionId: v.id("predictions"),
    followerId: v.id("users"),
  })
    .index("by_prediction", ["predictionId"])
    .index("by_follower", ["followerId"])
    .index("by_prediction_and_follower", ["predictionId", "followerId"]),

  // User relationships (trust)
  relationships: defineTable({
    subjectId: v.id("users"),
    objectId: v.id("users"),
    trusted: v.boolean(),
  })
    .index("by_subject", ["subjectId"])
    .index("by_object", ["objectId"])
    .index("by_subject_and_object", ["subjectId", "objectId"]),

  // Email invitations
  emailInvitations: defineTable({
    inviterId: v.id("users"),
    recipientEmail: v.string(),
    nonce: v.string(),
    createdAt: v.number(),
    acceptedAt: v.optional(v.number()),
    acceptedByUserId: v.optional(v.id("users")),
  })
    .index("by_nonce", ["nonce"])
    .index("by_inviter", ["inviterId"])
    .index("by_recipient", ["recipientEmail"]),
});
