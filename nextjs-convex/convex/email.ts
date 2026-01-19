"use node";

import { v } from "convex/values";
import { action, internalAction } from "./_generated/server";
import { internal } from "./_generated/api";
import * as React from "react";
import { render } from "@react-email/render";
import { VerificationEmail } from "../emails/VerificationEmail";
import { InvitationEmail } from "../emails/InvitationEmail";
import { ResolutionNotificationEmail } from "../emails/ResolutionNotificationEmail";
import { ResolutionReminderEmail } from "../emails/ResolutionReminderEmail";

// Email sending action using Resend
// You'll need to set RESEND_API_KEY in your Convex environment
export const sendEmail = internalAction({
  args: {
    to: v.string(),
    subject: v.string(),
    html: v.string(),
  },
  handler: async (ctx, args) => {
    const apiKey = process.env.RESEND_API_KEY;
    if (!apiKey) {
      console.log("RESEND_API_KEY not set, skipping email");
      console.log("Would send email to:", args.to);
      console.log("Subject:", args.subject);
      return { success: false, reason: "API key not configured" };
    }

    try {
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: process.env.EMAIL_FROM || "BIATOB <noreply@biatob.com>",
          to: args.to,
          subject: args.subject,
          html: args.html,
        }),
      });

      if (!response.ok) {
        const error = await response.text();
        console.error("Failed to send email:", error);
        return { success: false, reason: error };
      }

      return { success: true };
    } catch (error) {
      console.error("Email error:", error);
      return { success: false, reason: String(error) };
    }
  },
});

// Send verification email
export const sendVerificationEmail = action({
  args: {
    email: v.string(),
    code: v.string(),
  },
  handler: async (ctx, args) => {
    const html = await render(
      React.createElement(VerificationEmail, { code: args.code })
    );

    await ctx.runAction(internal.email.sendEmail, {
      to: args.email,
      subject: "Verify your email for BIATOB",
      html,
    });
  },
});

// Send invitation email
export const sendInvitationEmail = action({
  args: {
    recipientEmail: v.string(),
    inviterUsername: v.string(),
    nonce: v.string(),
    baseUrl: v.string(),
  },
  handler: async (ctx, args) => {
    const inviteUrl = `${args.baseUrl}/invite/${args.nonce}`;

    const html = await render(
      React.createElement(InvitationEmail, {
        inviterUsername: args.inviterUsername,
        inviteUrl,
      })
    );

    await ctx.runAction(internal.email.sendEmail, {
      to: args.recipientEmail,
      subject: `${args.inviterUsername} invited you to BIATOB`,
      html,
    });
  },
});

// Send resolution notification
export const sendResolutionNotification = action({
  args: {
    recipientEmail: v.string(),
    recipientUsername: v.string(),
    predictionText: v.string(),
    predictionId: v.string(),
    resolution: v.union(v.literal("yes"), v.literal("no"), v.literal("invalid")),
    creatorUsername: v.string(),
    baseUrl: v.string(),
  },
  handler: async (ctx, args) => {
    const predictionUrl = `${args.baseUrl}/p/${args.predictionId}`;

    const html = await render(
      React.createElement(ResolutionNotificationEmail, {
        recipientUsername: args.recipientUsername,
        predictionText: args.predictionText,
        predictionUrl,
        resolution: args.resolution,
        creatorUsername: args.creatorUsername,
      })
    );

    await ctx.runAction(internal.email.sendEmail, {
      to: args.recipientEmail,
      subject: `Prediction resolved: ${args.predictionText.slice(0, 50)}...`,
      html,
    });
  },
});

// Send resolution reminder
export const sendResolutionReminder = action({
  args: {
    creatorEmail: v.string(),
    creatorUsername: v.string(),
    predictionText: v.string(),
    predictionId: v.string(),
    resolvesAt: v.string(),
    totalStaked: v.string(),
    baseUrl: v.string(),
  },
  handler: async (ctx, args) => {
    const predictionUrl = `${args.baseUrl}/p/${args.predictionId}`;

    const html = await render(
      React.createElement(ResolutionReminderEmail, {
        creatorUsername: args.creatorUsername,
        predictionText: args.predictionText,
        predictionUrl,
        resolvesAt: args.resolvesAt,
        totalStaked: args.totalStaked,
      })
    );

    await ctx.runAction(internal.email.sendEmail, {
      to: args.creatorEmail,
      subject: `Time to resolve: ${args.predictionText.slice(0, 50)}...`,
      html,
    });
  },
});
