import { convexTest } from "convex-test";
import { expect, test, describe } from "vitest";
import { api } from "./_generated/api";
import { modules, schema } from "./testHelpers";

// Helper to create a user directly in the database and return authenticated context
async function setupAuthenticatedUser(
  t: ReturnType<typeof convexTest>,
  userData: { username: string; email: string }
) {
  const userId = await t.run(async (ctx) => {
    return await ctx.db.insert("users", {
      username: userData.username,
      email: userData.email,
      createdAt: Date.now(),
    });
  });

  const authedT = t.withIdentity({ subject: `${userId}|test-session` });
  return { userId, t: authedT };
}

describe("Relationships", () => {
  describe("setTrusted", () => {
    test("can trust another user", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });
      const { userId: bobId } = await setupAuthenticatedUser(t, {
        username: "bob",
        email: "bob@example.com",
      });

      await aliceT.mutation(api.relationships.setTrusted, {
        targetUsername: "bob",
        trusted: true,
      });

      const relationships = await t.run(async (ctx) => {
        return await ctx.db.query("relationships").collect();
      });

      expect(relationships.length).toBe(1);
      expect(relationships[0].trusted).toBe(true);
    });

    test("can untrust a user", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });
      await setupAuthenticatedUser(t, {
        username: "bob",
        email: "bob@example.com",
      });

      // First trust
      await aliceT.mutation(api.relationships.setTrusted, {
        targetUsername: "bob",
        trusted: true,
      });

      // Then untrust
      await aliceT.mutation(api.relationships.setTrusted, {
        targetUsername: "bob",
        trusted: false,
      });

      const relationships = await t.run(async (ctx) => {
        return await ctx.db.query("relationships").collect();
      });

      expect(relationships[0].trusted).toBe(false);
    });

    test("rejects trusting nonexistent user", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      await expect(
        aliceT.mutation(api.relationships.setTrusted, {
          targetUsername: "nonexistent",
          trusted: true,
        })
      ).rejects.toThrow("User not found");
    });

    test("rejects unauthenticated request", async () => {
      const t = convexTest(schema, modules);
      await setupAuthenticatedUser(t, {
        username: "bob",
        email: "bob@example.com",
      });

      await expect(
        t.mutation(api.relationships.setTrusted, {
          targetUsername: "bob",
          trusted: true,
        })
      ).rejects.toThrow("Not authenticated");
    });
  });

  describe("getUser", () => {
    test("returns user profile", async () => {
      const t = convexTest(schema, modules);
      await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const result = await t.query(api.relationships.getUser, {
        username: "alice",
      });

      expect(result).not.toBeNull();
      expect(result?.username).toBe("alice");
    });

    test("returns null for nonexistent user", async () => {
      const t = convexTest(schema, modules);

      const result = await t.query(api.relationships.getUser, {
        username: "nonexistent",
      });

      expect(result).toBeNull();
    });
  });

  describe("sendInvitation", () => {
    test("creates invitation for new email", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const result = await aliceT.mutation(api.relationships.sendInvitation, {
        recipientEmail: "newuser@example.com",
      });

      expect(result.nonce).toBeDefined();
      expect(result.nonce!.length).toBeGreaterThan(0);

      // Check invitation was created
      const invitations = await t.run(async (ctx) => {
        return await ctx.db.query("emailInvitations").collect();
      });

      expect(invitations.length).toBe(1);
      expect(invitations[0].recipientEmail).toBe("newuser@example.com");
    });

    test("normalizes email to lowercase", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      await aliceT.mutation(api.relationships.sendInvitation, {
        recipientEmail: "NEWUSER@EXAMPLE.COM",
      });

      const invitations = await t.run(async (ctx) => {
        return await ctx.db.query("emailInvitations").collect();
      });

      expect(invitations[0].recipientEmail).toBe("newuser@example.com");
    });

    test("rejects unauthenticated request", async () => {
      const t = convexTest(schema, modules);

      await expect(
        t.mutation(api.relationships.sendInvitation, {
          recipientEmail: "test@example.com",
        })
      ).rejects.toThrow("Not authenticated");
    });
  });

  describe("checkInvitation", () => {
    test("returns invitation info", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const invitation = await aliceT.mutation(api.relationships.sendInvitation, {
        recipientEmail: "newuser@example.com",
      });

      const result = await t.query(api.relationships.checkInvitation, {
        nonce: invitation.nonce!,
      });

      expect(result).not.toBeNull();
      expect(result?.inviterUsername).toBe("alice");
    });

    test("returns null for invalid nonce", async () => {
      const t = convexTest(schema, modules);

      const result = await t.query(api.relationships.checkInvitation, {
        nonce: "invalid-nonce",
      });

      expect(result).toBeNull();
    });
  });

  describe("acceptInvitation", () => {
    test("accepts invitation and creates mutual trust", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT, userId: aliceId } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });
      // Create bob without the same email that will be invited
      const { t: bobT, userId: bobId } = await setupAuthenticatedUser(t, {
        username: "bob",
        email: "different@example.com",
      });

      // Alice invites a new email
      const invitation = await aliceT.mutation(api.relationships.sendInvitation, {
        recipientEmail: "newemail@example.com",
      });

      // Bob accepts the invitation
      await bobT.mutation(api.relationships.acceptInvitation, {
        nonce: invitation.nonce!,
      });

      // Check mutual trust was created
      const relationships = await t.run(async (ctx) => {
        return await ctx.db.query("relationships").collect();
      });

      // Should have 2 relationships (alice->bob and bob->alice)
      expect(relationships.length).toBe(2);
      const allTrusted = relationships.every((r) => r.trusted);
      expect(allTrusted).toBe(true);
    });

    test("rejects invalid nonce", async () => {
      const t = convexTest(schema, modules);
      const { t: bobT } = await setupAuthenticatedUser(t, {
        username: "bob",
        email: "bob@example.com",
      });

      await expect(
        bobT.mutation(api.relationships.acceptInvitation, {
          nonce: "invalid-nonce",
        })
      ).rejects.toThrow("Invalid invitation");
    });

    test("rejects unauthenticated request", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const invitation = await aliceT.mutation(api.relationships.sendInvitation, {
        recipientEmail: "newuser@example.com",
      });

      await expect(
        t.mutation(api.relationships.acceptInvitation, {
          nonce: invitation.nonce!,
        })
      ).rejects.toThrow("Not authenticated");
    });
  });

  describe("getSettings", () => {
    test("returns user settings", async () => {
      const t = convexTest(schema, modules);
      const { t: aliceT } = await setupAuthenticatedUser(t, {
        username: "alice",
        email: "alice@example.com",
      });

      const result = await aliceT.query(api.relationships.getSettings, {});

      expect(result).not.toBeNull();
      expect(result?.user?.username).toBe("alice");
    });

    test("rejects unauthenticated request", async () => {
      const t = convexTest(schema, modules);

      await expect(t.query(api.relationships.getSettings, {})).rejects.toThrow(
        "Not authenticated"
      );
    });
  });
});
