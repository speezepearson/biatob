import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  // Users table
  users: defineTable({
    username: v.string(),
    email: v.string(),
    passwordHash: v.string(), // scrypt hash stored as base64
    passwordSalt: v.string(), // salt stored as base64
    createdAt: v.number(),
  })
    .index("by_username", ["username"])
    .index("by_email", ["email"]),

  // Predictions table
  predictions: defineTable({
    predictionId: v.string(), // human-readable ID
    prediction: v.string(), // the prediction text
    certaintyLowP: v.number(), // 0-1 probability range low
    certaintyHighP: v.number(), // 0-1 probability range high
    maximumStakeCents: v.number(),
    createdAt: v.number(),
    closesAt: v.number(), // when betting stops
    resolvesAt: v.number(), // expected resolution date
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
    bettorIsSkeptic: v.boolean(), // false = believer (YES), true = skeptic (NO)
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

  // Resolutions table (supports revision history)
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
    subjectId: v.id("users"), // the one doing the trusting
    objectId: v.id("users"), // the one being trusted
    trusted: v.boolean(),
  })
    .index("by_subject", ["subjectId"])
    .index("by_object", ["objectId"])
    .index("by_subject_and_object", ["subjectId", "objectId"]),

  // Email invitations
  emailInvitations: defineTable({
    inviterId: v.id("users"),
    recipientEmail: v.string(),
    nonce: v.string(), // unique token for acceptance
    createdAt: v.number(),
    acceptedAt: v.optional(v.number()),
    acceptedByUserId: v.optional(v.id("users")),
  })
    .index("by_nonce", ["nonce"])
    .index("by_inviter", ["inviterId"])
    .index("by_recipient", ["recipientEmail"]),

  // Email verification tokens
  emailVerifications: defineTable({
    email: v.string(),
    code: v.string(),
    createdAt: v.number(),
    expiresAt: v.number(),
    verified: v.boolean(),
  })
    .index("by_email", ["email"])
    .index("by_email_and_code", ["email", "code"]),

  // Auth sessions
  sessions: defineTable({
    userId: v.id("users"),
    token: v.string(),
    createdAt: v.number(),
    expiresAt: v.number(),
  })
    .index("by_token", ["token"])
    .index("by_user", ["userId"]),
});
