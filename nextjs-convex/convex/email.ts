"use node";

import { v } from "convex/values";
import { action, internalAction } from "./_generated/server";
import { internal } from "./_generated/api";

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
    const html = `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <h1 style="color: #2563eb;">Welcome to BIATOB</h1>
        <p>Your verification code is:</p>
        <div style="background: #f3f4f6; padding: 20px; text-align: center; font-size: 32px; font-weight: bold; letter-spacing: 8px; margin: 20px 0;">
          ${args.code}
        </div>
        <p>This code will expire in 24 hours.</p>
        <p style="color: #6b7280; font-size: 14px;">
          If you didn't request this code, you can safely ignore this email.
        </p>
      </div>
    `;

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

    const html = `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <h1 style="color: #2563eb;">You've been invited to BIATOB</h1>
        <p><strong>${args.inviterUsername}</strong> has invited you to join BIATOB, an honor-based prediction market platform.</p>
        <p>By accepting this invitation, you'll establish mutual trust with ${args.inviterUsername}, allowing you to bet on each other's predictions.</p>
        <div style="margin: 30px 0;">
          <a href="${inviteUrl}" style="background: #2563eb; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px;">
            Accept Invitation
          </a>
        </div>
        <p style="color: #6b7280; font-size: 14px;">
          Or copy this link: ${inviteUrl}
        </p>
      </div>
    `;

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
    resolution: v.string(),
    creatorUsername: v.string(),
    baseUrl: v.string(),
  },
  handler: async (ctx, args) => {
    const predictionUrl = `${args.baseUrl}/p/${args.predictionId}`;
    const resolutionColor =
      args.resolution === "yes"
        ? "#16a34a"
        : args.resolution === "no"
        ? "#dc2626"
        : "#ca8a04";

    const html = `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <h1 style="color: #2563eb;">Prediction Resolved</h1>
        <p>Hi ${args.recipientUsername},</p>
        <p>A prediction you're following has been resolved by ${args.creatorUsername}:</p>
        <div style="background: #f3f4f6; padding: 20px; margin: 20px 0; border-radius: 8px;">
          <p style="margin: 0 0 10px 0; font-weight: bold;">${args.predictionText}</p>
          <p style="margin: 0; font-size: 18px; color: ${resolutionColor}; font-weight: bold;">
            Resolved: ${args.resolution.toUpperCase()}
          </p>
        </div>
        <div style="margin: 30px 0;">
          <a href="${predictionUrl}" style="background: #2563eb; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px;">
            View Prediction
          </a>
        </div>
      </div>
    `;

    await ctx.runAction(internal.email.sendEmail, {
      to: args.recipientEmail,
      subject: `Prediction resolved: ${args.predictionText.slice(0, 50)}...`,
      html,
    });
  },
});
