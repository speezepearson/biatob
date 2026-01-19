"use node";

import { internalAction, internalMutation } from "./_generated/server";
import { internal } from "./_generated/api";
import * as React from "react";
import { render } from "@react-email/render";
import { ResolutionReminderEmail } from "../emails/ResolutionReminderEmail";

// Internal mutation to get predictions needing reminders
export const getPredictionsNeedingReminders = internalMutation({
  handler: async (ctx) => {
    const now = Date.now();
    const oneDayFromNow = now + 24 * 60 * 60 * 1000;

    // Get predictions that resolve within the next day and haven't had a reminder sent
    const predictions = await ctx.db
      .query("predictions")
      .withIndex("by_resolvesAt")
      .filter((q) =>
        q.and(
          q.lte(q.field("resolvesAt"), oneDayFromNow),
          q.gte(q.field("resolvesAt"), now),
          q.eq(q.field("resolutionReminderSent"), false)
        )
      )
      .collect();

    // Get creator info and check if already resolved
    const results = [];
    for (const prediction of predictions) {
      const resolution = await ctx.db
        .query("resolutions")
        .withIndex("by_prediction", (q) => q.eq("predictionId", prediction._id))
        .first();

      if (!resolution || resolution.resolution === "none_yet") {
        const creator = await ctx.db.get(prediction.creatorId);
        if (creator) {
          // Calculate total staked
          const trades = await ctx.db
            .query("trades")
            .withIndex("by_prediction", (q) => q.eq("predictionId", prediction._id))
            .collect();
          const activeTrades = trades.filter((t) => t.state === "active");
          const totalStakedCents = activeTrades.reduce(
            (sum, t) => sum + t.bettorStakeCents + t.creatorStakeCents,
            0
          );

          results.push({
            predictionId: prediction._id,
            predictionTextId: prediction.predictionId,
            predictionText: prediction.prediction,
            creatorEmail: creator.email,
            creatorUsername: creator.username,
            resolvesAt: prediction.resolvesAt,
            totalStakedCents,
          });

          // Mark reminder as sent
          await ctx.db.patch(prediction._id, { resolutionReminderSent: true });
        }
      }
    }

    return results;
  },
});

// Action to send resolution reminder emails
export const sendResolutionReminders = internalAction({
  handler: async (ctx) => {
    const predictions = await ctx.runMutation(
      internal.scheduled.getPredictionsNeedingReminders
    );

    const baseUrl = process.env.BASE_URL || "https://biatob.com";

    for (const prediction of predictions) {
      const predictionUrl = `${baseUrl}/p/${prediction.predictionTextId}`;
      const resolvesDate = new Date(prediction.resolvesAt).toLocaleDateString(
        "en-US",
        { year: "numeric", month: "long", day: "numeric" }
      );
      const totalStaked = `$${(prediction.totalStakedCents / 100).toFixed(2)}`;

      const html = await render(
        React.createElement(ResolutionReminderEmail, {
          creatorUsername: prediction.creatorUsername || "there",
          predictionText: prediction.predictionText,
          predictionUrl,
          resolvesAt: resolvesDate,
          totalStaked,
        })
      );

      await ctx.runAction(internal.email.sendEmail, {
        to: prediction.creatorEmail || "",
        subject: `Time to resolve: ${prediction.predictionText.slice(0, 50)}...`,
        html,
      });
    }

    return { sent: predictions.length };
  },
});
