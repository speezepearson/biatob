import { convexTest } from "convex-test";
import { expect } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

// Test time utilities
export class MockClock {
  private currentTime: number;

  constructor(initialTime: number = Date.now()) {
    this.currentTime = initialTime;
  }

  now(): number {
    return this.currentTime;
  }

  advance(ms: number): void {
    this.currentTime += ms;
  }

  advanceDays(days: number): void {
    this.advance(days * 24 * 60 * 60 * 1000);
  }

  set(time: number): void {
    this.currentTime = time;
  }
}

// Email capture for testing
export interface CapturedEmail {
  to: string;
  subject: string;
  html: string;
}

export class EmailCapture {
  emails: CapturedEmail[] = [];

  capture(email: CapturedEmail): void {
    this.emails.push(email);
  }

  clear(): void {
    this.emails = [];
  }

  getLastEmail(): CapturedEmail | undefined {
    return this.emails[this.emails.length - 1];
  }

  getEmailsTo(recipient: string): CapturedEmail[] {
    return this.emails.filter((e) => e.to === recipient);
  }
}

// Create a test context with Convex
export function createTestContext() {
  return convexTest(schema);
}

// Test fixtures
export const testUsers = {
  alice: {
    username: "alice",
    email: "alice@example.com",
    password: "password123",
  },
  bob: {
    username: "bob",
    email: "bob@example.com",
    password: "password456",
  },
  charlie: {
    username: "charlie",
    email: "charlie@example.com",
    password: "password789",
  },
};

// Helper to create a user and get their token
export async function createUser(
  t: ReturnType<typeof convexTest>,
  user: { username: string; email: string; password: string }
) {
  // Create email verification
  await t.mutation(api.auth.createEmailVerification, { email: user.email });

  // Get the verification code from the database
  const verifications = await t.run(async (ctx) => {
    return await ctx.db.query("emailVerifications").collect();
  });
  const verification = verifications.find((v) => v.email === user.email);
  if (!verification) throw new Error("No verification found");

  // Verify the code
  await t.mutation(api.auth.verifyEmailCode, {
    email: user.email,
    code: verification.code,
  });

  // Register the user
  const result = await t.mutation(api.auth.register, {
    username: user.username,
    email: user.email,
    password: user.password,
  });

  return result.token;
}

// Helper to create a prediction
export async function createPrediction(
  t: ReturnType<typeof convexTest>,
  token: string,
  options: {
    prediction?: string;
    certaintyLowP?: number;
    certaintyHighP?: number;
    maximumStakeCents?: number;
    closesAt?: number;
    resolvesAt?: number;
    specialRules?: string;
    viewPrivacy?: "public" | "link_only";
  } = {}
) {
  const now = Date.now();
  const result = await t.mutation(api.predictions.create, {
    token,
    prediction: options.prediction ?? "Test prediction",
    certaintyLowP: options.certaintyLowP ?? 0.6,
    certaintyHighP: options.certaintyHighP ?? 0.8,
    maximumStakeCents: options.maximumStakeCents ?? 10000,
    closesAt: options.closesAt ?? now + 7 * 24 * 60 * 60 * 1000,
    resolvesAt: options.resolvesAt ?? now + 30 * 24 * 60 * 60 * 1000,
    specialRules: options.specialRules,
    viewPrivacy: options.viewPrivacy ?? "public",
  });
  return result.predictionId;
}

// Helper to place a stake
export async function placeStake(
  t: ReturnType<typeof convexTest>,
  token: string,
  predictionId: string,
  options: {
    bettorIsSkeptic?: boolean;
    bettorStakeCents?: number;
    notes?: string;
  } = {}
) {
  return await t.mutation(api.trades.stake, {
    token,
    predictionId,
    bettorIsSkeptic: options.bettorIsSkeptic ?? false,
    bettorStakeCents: options.bettorStakeCents ?? 1000,
    notes: options.notes,
  });
}

// Helper to resolve a prediction
export async function resolvePrediction(
  t: ReturnType<typeof convexTest>,
  token: string,
  predictionId: string,
  resolution: "yes" | "no" | "invalid",
  notes?: string
) {
  return await t.mutation(api.predictions.resolve, {
    token,
    predictionId,
    resolution,
    notes,
  });
}

// Helper to establish mutual trust
export async function establishMutualTrust(
  t: ReturnType<typeof convexTest>,
  token1: string,
  username2: string,
  token2: string,
  username1: string
) {
  await t.mutation(api.relationships.setTrusted, {
    token: token1,
    targetUsername: username2,
    trusted: true,
  });
  await t.mutation(api.relationships.setTrusted, {
    token: token2,
    targetUsername: username1,
    trusted: true,
  });
}

// Assertion helpers
export function expectError(fn: () => Promise<any>, messageContains?: string) {
  return expect(fn()).rejects.toThrow(messageContains);
}
