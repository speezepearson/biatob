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

// Generate a random nonce
function generateNonce(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  let result = "";
  for (let i = 0; i < 64; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

// Set trust relationship
export const setTrusted = mutation({
  args: {
    token: v.string(),
    targetUsername: v.string(),
    trusted: v.boolean(),
  },
  handler: async (ctx, args) => {
    const user = await getUserFromSession(ctx, args.token);
    if (!user) {
      throw new Error("Not authenticated");
    }

    const targetUser = await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", args.targetUsername))
      .first();

    if (!targetUser) {
      throw new Error("User not found");
    }

    if (targetUser._id === user._id) {
      throw new Error("Cannot set trust relationship with yourself");
    }

    const existingRelationship = await ctx.db
      .query("relationships")
      .withIndex("by_subject_and_object", (q) =>
        q.eq("subjectId", user._id).eq("objectId", targetUser._id)
      )
      .first();

    if (existingRelationship) {
      await ctx.db.patch(existingRelationship._id, { trusted: args.trusted });
    } else {
      await ctx.db.insert("relationships", {
        subjectId: user._id,
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
    token: v.optional(v.string()),
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

    if (args.token) {
      const currentUser = await getUserFromSession(ctx, args.token);
      if (currentUser && currentUser._id !== targetUser._id) {
        // Check if I trust them
        const myTrust = await ctx.db
          .query("relationships")
          .withIndex("by_subject_and_object", (q) =>
            q.eq("subjectId", currentUser._id).eq("objectId", targetUser._id)
          )
          .first();
        isTrustedByMe = myTrust?.trusted ?? false;

        // Check if they trust me
        const theirTrust = await ctx.db
          .query("relationships")
          .withIndex("by_subject_and_object", (q) =>
            q.eq("subjectId", targetUser._id).eq("objectId", currentUser._id)
          )
          .first();
        trustsMe = theirTrust?.trusted ?? false;
      }
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
      createdAt: targetUser.createdAt,
      isTrustedByMe,
      trustsMe,
      mutualTrust: isTrustedByMe && trustsMe,
      recentPredictions: predictions,
    };
  },
});

// Get user settings and relationships
export const getSettings = query({
  args: { token: v.string() },
  handler: async (ctx, args) => {
    const user = await getUserFromSession(ctx, args.token);
    if (!user) {
      throw new Error("Not authenticated");
    }

    // Get people I trust
    const myTrustRelations = await ctx.db
      .query("relationships")
      .withIndex("by_subject", (q) => q.eq("subjectId", user._id))
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
              q.eq("subjectId", r.objectId).eq("objectId", user._id)
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
      .withIndex("by_object", (q) => q.eq("objectId", user._id))
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
      .withIndex("by_inviter", (q) => q.eq("inviterId", user._id))
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
        createdAt: i.createdAt,
        accepted: !!i.acceptedAt,
      })),
    };
  },
});

// Send invitation
export const sendInvitation = mutation({
  args: {
    token: v.string(),
    recipientEmail: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await getUserFromSession(ctx, args.token);
    if (!user) {
      throw new Error("Not authenticated");
    }

    const email = args.recipientEmail.toLowerCase().trim();

    // Check if already invited
    const existingInvitation = await ctx.db
      .query("emailInvitations")
      .withIndex("by_inviter", (q) => q.eq("inviterId", user._id))
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
      .withIndex("by_email", (q) => q.eq("email", email))
      .first();

    if (existingUser) {
      // Just create mutual trust
      await ctx.db.insert("relationships", {
        subjectId: user._id,
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
      inviterId: user._id,
      recipientEmail: email,
      nonce,
      createdAt: Date.now(),
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
    token: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await getUserFromSession(ctx, args.token);
    if (!user) {
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
      acceptedByUserId: user._id,
    });

    // Create mutual trust
    // Inviter trusts recipient
    await ctx.db.insert("relationships", {
      subjectId: invitation.inviterId,
      objectId: user._id,
      trusted: true,
    });

    // Recipient trusts inviter
    await ctx.db.insert("relationships", {
      subjectId: user._id,
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
