"use node";

import { internalAction, internalMutation } from "./_generated/server";
import { internal } from "./_generated/api";

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
          results.push({
            predictionId: prediction._id,
            predictionTextId: prediction.predictionId,
            predictionText: prediction.prediction,
            creatorEmail: creator.email,
            creatorUsername: creator.username,
            resolvesAt: prediction.resolvesAt,
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
      const resolvesDate = new Date(prediction.resolvesAt).toLocaleDateString();

      const html = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
          <h1 style="color: #2563eb;">Resolution Reminder</h1>
          <p>Hi ${prediction.creatorUsername},</p>
          <p>Your prediction is due to be resolved by <strong>${resolvesDate}</strong>:</p>
          <div style="background: #f3f4f6; padding: 20px; margin: 20px 0; border-radius: 8px;">
            <p style="margin: 0; font-weight: bold;">${prediction.predictionText}</p>
          </div>
          <p>Please resolve this prediction when you have the answer.</p>
          <div style="margin: 30px 0;">
            <a href="${predictionUrl}" style="background: #2563eb; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px;">
              Resolve Prediction
            </a>
          </div>
        </div>
      `;

      await ctx.runAction(internal.email.sendEmail, {
        to: prediction.creatorEmail,
        subject: `Reminder: Your prediction is due for resolution`,
        html,
      });
    }

    return { sent: predictions.length };
  },
});
