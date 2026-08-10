import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

// Send resolution reminders daily at 9 AM UTC
crons.daily(
  "resolution reminders",
  { hourUTC: 9, minuteUTC: 0 },
  internal.scheduled.sendResolutionReminders
);

export default crons;
