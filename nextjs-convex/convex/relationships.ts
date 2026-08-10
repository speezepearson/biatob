import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { auth } from "./auth";
import { getCreationTime } from "./helpers";

// Generate a cryptographically secure random nonce
function generateNonce(): string {
  const bytes = new Uint8Array(48); // 48 bytes = 64 base64 chars
  crypto.getRandomValues(bytes);
  // Convert to base64url (URL-safe)
  const base64 = btoa(String.fromCharCode(...bytes));
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

// Set trust relationship
export const setTrusted = mutation({
  args: {
    targetUsername: v.string(),
    trusted: v.boolean(),
  },
  handler: async (ctx, args) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) {
      throw new Error("Not authenticated");
    }

    const user = await ctx.db.get(userId);
    if (!user) {
      throw new Error("User not found");
    }

    const targetUser = await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", args.targetUsername))
      .first();

    if (!targetUser) {
      throw new Error("User not found");
    }

    if (targetUser._id === userId) {
      throw new Error("Cannot set trust relationship with yourself");
    }

    const existingRelationship = await ctx.db
      .query("relationships")
      .withIndex("by_subject_and_object", (q) =>
        q.eq("subjectId", userId).eq("objectId", targetUser._id)
      )
      .first();

    if (existingRelationship) {
      await ctx.db.patch(existingRelationship._id, { trusted: args.trusted });
    } else {
      await ctx.db.insert("relationships", {
        subjectId: userId,
        objectId: targetUser._id,
        trusted: args.trusted,
      });
    }

    return { success: true };
  },
});

// Get user profile with relationship info
export const getUser = query({
  args: {
    username: v.string(),
  },
  handler: async (ctx, args) => {
    const targetUser = await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", args.username))
      .first();

    if (!targetUser) {
      return null;
    }

    let isTrustedByMe = false;
    let trustsMe = false;

    const currentUserId = await auth.getUserId(ctx);
    if (currentUserId && currentUserId !== targetUser._id) {
      // Check if I trust them
      const myTrust = await ctx.db
        .query("relationships")
        .withIndex("by_subject_and_object", (q) =>
          q.eq("subjectId", currentUserId).eq("objectId", targetUser._id)
        )
        .first();
      isTrustedByMe = myTrust?.trusted ?? false;

      // Check if they trust me
      const theirTrust = await ctx.db
        .query("relationships")
        .withIndex("by_subject_and_object", (q) =>
          q.eq("subjectId", targetUser._id).eq("objectId", currentUserId)
        )
        .first();
      trustsMe = theirTrust?.trusted ?? false;
    }

    // Get their predictions
    const predictions = await ctx.db
      .query("predictions")
      .withIndex("by_creator", (q) => q.eq("creatorId", targetUser._id))
      .order("desc")
      .take(10);

    return {
      _id: targetUser._id,
      username: targetUser.username,
      createdAt: getCreationTime(targetUser),
      isTrustedByMe,
      trustsMe,
      mutualTrust: isTrustedByMe && trustsMe,
      recentPredictions: predictions,
    };
  },
});

// Get user settings and relationships
export const getSettings = query({
  args: {},
  handler: async (ctx) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) {
      throw new Error("Not authenticated");
    }

    const user = await ctx.db.get(userId);
    if (!user) {
      throw new Error("User not found");
    }

    // Get people I trust
    const myTrustRelations = await ctx.db
      .query("relationships")
      .withIndex("by_subject", (q) => q.eq("subjectId", userId))
      .collect();

    const trustedUsers = await Promise.all(
      myTrustRelations
        .filter((r) => r.trusted)
        .map(async (r) => {
          const u = await ctx.db.get(r.objectId);
          if (!u) return null;

          // Check if they trust me back
          const theirTrust = await ctx.db
            .query("relationships")
            .withIndex("by_subject_and_object", (q) =>
              q.eq("subjectId", r.objectId).eq("objectId", userId)
            )
            .first();

          return {
            _id: u._id,
            username: u.username,
            trustsMe: theirTrust?.trusted ?? false,
          };
        })
    );

    // Get people who trust me
    const theirTrustRelations = await ctx.db
      .query("relationships")
      .withIndex("by_object", (q) => q.eq("objectId", userId))
      .collect();

    const trustedByUsers = await Promise.all(
      theirTrustRelations
        .filter((r) => r.trusted)
        .map(async (r) => {
          const u = await ctx.db.get(r.subjectId);
          if (!u) return null;

          // Check if I trust them back
          const myTrust = myTrustRelations.find(
            (m) => m.objectId === r.subjectId
          );

          return {
            _id: u._id,
            username: u.username,
            isTrustedByMe: myTrust?.trusted ?? false,
          };
        })
    );

    // Get pending invitations I sent
    const sentInvitations = await ctx.db
      .query("emailInvitations")
      .withIndex("by_inviter", (q) => q.eq("inviterId", userId))
      .collect();

    return {
      user: {
        _id: user._id,
        username: user.username,
        email: user.email,
      },
      trustedUsers: trustedUsers.filter((u) => u !== null),
      trustedByUsers: trustedByUsers.filter((u) => u !== null),
      sentInvitations: sentInvitations.map((i) => ({
        recipientEmail: i.recipientEmail,
        createdAt: getCreationTime(i),
        accepted: !!i.acceptedAt,
      })),
    };
  },
});

// Send invitation
export const sendInvitation = mutation({
  args: {
    recipientEmail: v.string(),
  },
  handler: async (ctx, args) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) {
      throw new Error("Not authenticated");
    }

    const user = await ctx.db.get(userId);
    if (!user) {
      throw new Error("User not found");
    }

    const email = args.recipientEmail.toLowerCase().trim();

    // Check if already invited
    const existingInvitation = await ctx.db
      .query("emailInvitations")
      .withIndex("by_inviter", (q) => q.eq("inviterId", userId))
      .collect();

    const alreadyInvited = existingInvitation.some(
      (i) => i.recipientEmail === email && !i.acceptedAt
    );

    if (alreadyInvited) {
      throw new Error("Already sent invitation to this email");
    }

    // Check if recipient is already a user
    const existingUser = await ctx.db
      .query("users")
      .withIndex("email", (q) => q.eq("email", email))
      .first();

    if (existingUser) {
      // Just create mutual trust
      await ctx.db.insert("relationships", {
        subjectId: userId,
        objectId: existingUser._id,
        trusted: true,
      });

      return {
        success: true,
        alreadyUser: true,
        nonce: null,
      };
    }

    const nonce = generateNonce();

    await ctx.db.insert("emailInvitations", {
      inviterId: userId,
      recipientEmail: email,
      nonce,
      // Note: _creationTime is set automatically; creationTimeOverride is only for migration
    });

    return {
      success: true,
      alreadyUser: false,
      nonce,
      inviterUsername: user.username,
    };
  },
});

// Check invitation
export const checkInvitation = query({
  args: { nonce: v.string() },
  handler: async (ctx, args) => {
    const invitation = await ctx.db
      .query("emailInvitations")
      .withIndex("by_nonce", (q) => q.eq("nonce", args.nonce))
      .first();

    if (!invitation) {
      return null;
    }

    if (invitation.acceptedAt) {
      return { alreadyAccepted: true };
    }

    const inviter = await ctx.db.get(invitation.inviterId);

    return {
      alreadyAccepted: false,
      inviterUsername: inviter?.username || "Unknown",
      recipientEmail: invitation.recipientEmail,
    };
  },
});

// Accept invitation
export const acceptInvitation = mutation({
  args: {
    nonce: v.string(),
  },
  handler: async (ctx, args) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) {
      throw new Error("Not authenticated");
    }

    const invitation = await ctx.db
      .query("emailInvitations")
      .withIndex("by_nonce", (q) => q.eq("nonce", args.nonce))
      .first();

    if (!invitation) {
      throw new Error("Invalid invitation");
    }

    if (invitation.acceptedAt) {
      throw new Error("Invitation already accepted");
    }

    // Mark invitation as accepted
    await ctx.db.patch(invitation._id, {
      acceptedAt: Date.now(),
      acceptedByUserId: userId,
    });

    // Create mutual trust
    // Inviter trusts recipient
    await ctx.db.insert("relationships", {
      subjectId: invitation.inviterId,
      objectId: userId,
      trusted: true,
    });

    // Recipient trusts inviter
    await ctx.db.insert("relationships", {
      subjectId: userId,
      objectId: invitation.inviterId,
      trusted: true,
    });

    const inviter = await ctx.db.get(invitation.inviterId);

    return {
      success: true,
      inviterUsername: inviter?.username || "Unknown",
    };
  },
});
