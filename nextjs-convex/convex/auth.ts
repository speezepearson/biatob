import { convexAuth } from "@convex-dev/auth/server";
import { Password } from "@convex-dev/auth/providers/Password";
import { query, mutation, action, internalMutation } from "./_generated/server";
import { v } from "convex/values";
import { DataModel } from "./_generated/dataModel";
import { scrypt } from "@noble/hashes/scrypt.js";
import { Scrypt } from "oslo/password";
import { internal } from "./_generated/api";

// Scrypt parameters - pinned to prevent breakage on library updates
const SCRYPT_PARAMS = { N: 16384, r: 8, p: 1, dkLen: 64 };

// Legacy Python system used these params: n=16384, r=8, p=1, dkLen=64
const LEGACY_SCRYPT_PARAMS = { N: 16384, r: 8, p: 1, dkLen: 64 };

/**
 * Hash format: "scrypt$N=16384,r=8,p=1,dkLen=64$<base64-salt>$<base64-hash>"
 * This self-describing format ensures we can always verify regardless of library defaults.
 */
function encodeHash(salt: Uint8Array, hash: Uint8Array, params: typeof SCRYPT_PARAMS): string {
  const saltB64 = btoa(String.fromCharCode(...salt));
  const hashB64 = btoa(String.fromCharCode(...hash));
  return `scrypt$N=${params.N},r=${params.r},p=${params.p},dkLen=${params.dkLen}$${saltB64}$${hashB64}`;
}

function decodeHash(encoded: string): { salt: Uint8Array; hash: Uint8Array; params: typeof SCRYPT_PARAMS } | null {
  const parts = encoded.split("$");
  if (parts.length !== 4 || parts[0] !== "scrypt") return null;

  const paramStr = parts[1];
  const paramMatch = paramStr.match(/N=(\d+),r=(\d+),p=(\d+),dkLen=(\d+)/);
  if (!paramMatch) return null;

  const params = {
    N: parseInt(paramMatch[1], 10),
    r: parseInt(paramMatch[2], 10),
    p: parseInt(paramMatch[3], 10),
    dkLen: parseInt(paramMatch[4], 10),
  };

  const saltB64 = parts[2];
  const hashB64 = parts[3];

  const salt = Uint8Array.from(atob(saltB64), (c) => c.charCodeAt(0));
  const hash = Uint8Array.from(atob(hashB64), (c) => c.charCodeAt(0));

  return { salt, hash, params };
}

/**
 * Timing-safe comparison for hash verification
 */
function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a[i] ^ b[i];
  }
  return result === 0;
}

/**
 * Verify a legacy password hash from the old Python system.
 * Old format: salt (4 bytes) + scrypt hash, with n=16384, r=8, p=1
 */
export function verifyLegacyPassword(
  password: string,
  saltB64: string,
  scryptB64: string
): boolean {
  const salt = Uint8Array.from(atob(saltB64), (c) => c.charCodeAt(0));
  const expectedHash = Uint8Array.from(atob(scryptB64), (c) => c.charCodeAt(0));

  const computed = scrypt(password, salt, {
    N: LEGACY_SCRYPT_PARAMS.N,
    r: LEGACY_SCRYPT_PARAMS.r,
    p: LEGACY_SCRYPT_PARAMS.p,
    dkLen: LEGACY_SCRYPT_PARAMS.dkLen,
  });

  return timingSafeEqual(computed, expectedHash);
}

// Custom crypto with self-describing hash format
const customCrypto = {
  async hashSecret(password: string): Promise<string> {
    // Generate 32-byte salt using crypto.getRandomValues
    const salt = new Uint8Array(32);
    crypto.getRandomValues(salt);

    const hash = scrypt(password, salt, {
      N: SCRYPT_PARAMS.N,
      r: SCRYPT_PARAMS.r,
      p: SCRYPT_PARAMS.p,
      dkLen: SCRYPT_PARAMS.dkLen,
    });

    return encodeHash(salt, hash, SCRYPT_PARAMS);
  },

  async verifySecret(password: string, encoded: string): Promise<boolean> {
    const decoded = decodeHash(encoded);
    if (!decoded) {
      // Fallback to oslo's Scrypt for any old hashes in oslo format (salt:hash)
      // This handles hashes created before we added the self-describing format
      try {
        return await new Scrypt().verify(encoded, password);
      } catch {
        return false;
      }
    }

    const { salt, hash: expectedHash, params } = decoded;
    const computed = scrypt(password, salt, {
      N: params.N,
      r: params.r,
      p: params.p,
      dkLen: params.dkLen,
    });

    return timingSafeEqual(computed, expectedHash);
  },
};

// Convex Auth setup with custom crypto
export const { auth, signIn, signOut, store } = convexAuth({
  providers: [
    Password<DataModel>({
      profile(params) {
        return {
          email: params.email as string,
          name: params.name as string | undefined,
        };
      },
      crypto: customCrypto,
    }),
  ],
});

// Internal mutation to migrate a legacy user to Convex Auth
export const migrateFromLegacy = internalMutation({
  args: {
    email: v.string(),
    username: v.string(),
    password: v.string(),
  },
  handler: async (ctx, args) => {
    // Hash the password with our new format
    const hashedPassword = await customCrypto.hashSecret(args.password);

    // Create the user in Convex Auth by inserting into the users table
    // and the authAccounts table
    const userId = await ctx.db.insert("users", {
      email: args.email,
      username: args.username,
      createdAt: Date.now(),
    });

    // Create auth account linked to this user
    // Note: This inserts directly into Convex Auth's internal tables
    await ctx.db.insert("authAccounts", {
      userId,
      provider: "password",
      providerAccountId: args.email.toLowerCase(),
      secret: hashedPassword,
    });

    // Delete the legacy password hash entry
    const legacyEntry = await ctx.db
      .query("legacyPasswordHashes")
      .withIndex("by_email", (q) => q.eq("email", args.email.toLowerCase()))
      .first();

    if (legacyEntry) {
      await ctx.db.delete(legacyEntry._id);
    }

    return { userId };
  },
});

// Check if a user exists in the legacy password table and verify their password
export const checkLegacyUser = query({
  args: { email: v.string() },
  handler: async (ctx, args) => {
    const legacyEntry = await ctx.db
      .query("legacyPasswordHashes")
      .withIndex("by_email", (q) => q.eq("email", args.email.toLowerCase()))
      .first();

    if (!legacyEntry) {
      return null;
    }

    return {
      exists: true,
      username: legacyEntry.username,
      // Don't return salt/hash to client
    };
  },
});

// Action to attempt sign-in with legacy migration
// This tries legacy auth first, migrates if successful, then uses normal auth
export const signInWithLegacyMigration = action({
  args: {
    email: v.string(),
    password: v.string(),
  },
  handler: async (ctx, args): Promise<{ success: boolean; migrated?: boolean; error?: string }> => {
    const email = args.email.toLowerCase();

    // Check for legacy user
    const legacyEntry = await ctx.runQuery(internal.auth.getLegacyPasswordHash, {
      email,
    });

    if (legacyEntry) {
      // Verify against legacy hash
      const isValid = verifyLegacyPassword(
        args.password,
        legacyEntry.salt,
        legacyEntry.scrypt
      );

      if (isValid) {
        // Migrate the user to Convex Auth
        await ctx.runMutation(internal.auth.migrateFromLegacy, {
          email,
          username: legacyEntry.username,
          password: args.password,
        });

        return { success: true, migrated: true };
      } else {
        return { success: false, error: "Invalid password" };
      }
    }

    // No legacy user - they should use normal Convex Auth sign-in
    return { success: false, error: "User not found in legacy system" };
  },
});

// Internal query to get legacy password hash (not exposed to client)
export const getLegacyPasswordHash = query({
  args: { email: v.string() },
  handler: async (ctx, args) => {
    const legacyEntry = await ctx.db
      .query("legacyPasswordHashes")
      .withIndex("by_email", (q) => q.eq("email", args.email.toLowerCase()))
      .first();

    if (!legacyEntry) return null;

    return {
      username: legacyEntry.username,
      salt: legacyEntry.salt,
      scrypt: legacyEntry.scrypt,
    };
  },
});

// Get the current user (using Convex Auth)
export const currentUser = query({
  args: {},
  handler: async (ctx) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) return null;

    const user = await ctx.db.get(userId);
    if (!user) return null;

    return {
      _id: user._id,
      username: user.username,
      email: user.email,
      name: user.name,
      createdAt: user.createdAt,
    };
  },
});

// Set username for the current user (after initial auth)
export const setUsername = mutation({
  args: { username: v.string() },
  handler: async (ctx, args) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) {
      throw new Error("Not authenticated");
    }

    const username = args.username.trim();

    // Validate username
    if (!/^[a-zA-Z0-9_]{3,32}$/.test(username)) {
      throw new Error(
        "Username must be 3-32 characters, alphanumeric and underscores only"
      );
    }

    // Check if username is taken
    const existingUsername = await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", username))
      .first();

    if (existingUsername && existingUsername._id !== userId) {
      throw new Error("Username already taken");
    }

    // Update user
    await ctx.db.patch(userId, {
      username,
      createdAt: Date.now(),
    });

    return { success: true };
  },
});

// Get user by ID
export const getUserById = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const user = await ctx.db.get(args.userId);
    if (!user) return null;

    return {
      _id: user._id,
      username: user.username,
      email: user.email,
      name: user.name,
      createdAt: user.createdAt,
    };
  },
});

// Legacy exports for backward compatibility (using Convex Auth internally)
// These are wrappers around Convex Auth that maintain the old API

export const getCurrentUser = query({
  args: {},
  handler: async (ctx) => {
    const userId = await auth.getUserId(ctx);
    if (!userId) return null;

    const user = await ctx.db.get(userId);
    if (!user) return null;

    return {
      _id: user._id,
      username: user.username,
      email: user.email,
      createdAt: user.createdAt,
    };
  },
});
