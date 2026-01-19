#!/usr/bin/env npx ts-node
/**
 * Migration script: MySQL → Convex JSONL files
 *
 * Usage:
 *   npx ts-node scripts/migrate-from-mysql.ts "mysql://user:pass@host/dbname"
 *
 * Or with SQLite:
 *   npx ts-node scripts/migrate-from-mysql.ts "sqlite:///path/to/db.sqlite"
 *
 * Output files (in ./migration-output/):
 *   - users.jsonl
 *   - legacyPasswordHashes.jsonl
 *   - predictions.jsonl
 *   - trades.jsonl
 *   - resolutions.jsonl
 *   - predictionFollows.jsonl
 *   - relationships.jsonl
 *   - emailInvitations.jsonl
 */

import * as fs from "fs";
import * as path from "path";

// Type definitions for old schema
interface OldPassword {
  password_id: string;
  salt: Buffer;
  scrypt: Buffer;
}

interface OldUser {
  username: string;
  login_password_id: string;
  email_address: string;
}

interface OldPrediction {
  prediction_id: string;
  prediction: string;
  certainty_low_p: number;
  certainty_high_p: number;
  maximum_stake_cents: number;
  created_at_unixtime: number;
  closes_at_unixtime: number;
  resolves_at_unixtime: number;
  special_rules: string;
  creator: string;
  resolution_reminder_sent: boolean | number;
  view_privacy: string;
}

interface OldTrade {
  prediction_id: string;
  bettor: string;
  transacted_at_unixtime: number;
  bettor_is_a_skeptic: boolean | number;
  bettor_stake_cents: number;
  creator_stake_cents: number;
  state: string;
  updated_at_unixtime: number;
  notes: string;
}

interface OldResolution {
  prediction_id: string;
  resolved_at_unixtime: number;
  resolution: string;
  notes: string;
}

interface OldPredictionFollow {
  prediction_id: string;
  follower: string;
}

interface OldRelationship {
  subject_username: string;
  object_username: string;
  trusted: boolean | number;
}

interface OldEmailInvitation {
  inviter: string;
  recipient: string;
  nonce: string;
}

// ID mapping: old username → new placeholder ID
// In actual import, these will be replaced with real Convex IDs
const userIdMap = new Map<string, string>();
const predictionIdMap = new Map<string, string>();

function generatePlaceholderId(prefix: string, index: number): string {
  // These placeholders will be replaced during Convex import
  return `__${prefix}_${index}__`;
}

function writeJsonl(filename: string, records: unknown[]): void {
  const outputDir = path.join(process.cwd(), "migration-output");
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  const filepath = path.join(outputDir, filename);
  const content = records.map((r) => JSON.stringify(r)).join("\n");
  fs.writeFileSync(filepath, content + "\n");
  console.log(`Wrote ${records.length} records to ${filepath}`);
}

function mapViewPrivacy(old: string): "public" | "link_only" {
  if (old === "PREDICTION_VIEW_PRIVACY_ANYBODY_WITH_THE_LINK") {
    return "link_only";
  }
  return "public";
}

function mapTradeState(old: string): "active" | "queued" | "disavowed" | "dequeue_failed" {
  const mapping: Record<string, "active" | "queued" | "disavowed" | "dequeue_failed"> = {
    TRADE_STATE_ACTIVE: "active",
    TRADE_STATE_QUEUED: "queued",
    TRADE_STATE_DISAVOWED: "disavowed",
    TRADE_STATE_DEQUEUE_FAILED: "dequeue_failed",
  };
  return mapping[old] || "active";
}

function mapResolution(old: string): "none_yet" | "yes" | "no" | "invalid" {
  const mapping: Record<string, "none_yet" | "yes" | "no" | "invalid"> = {
    RESOLUTION_NONE_YET: "none_yet",
    RESOLUTION_YES: "yes",
    RESOLUTION_NO: "no",
    RESOLUTION_INVALID: "invalid",
  };
  return mapping[old] || "none_yet";
}

function toBool(val: boolean | number | null | undefined): boolean {
  if (typeof val === "boolean") return val;
  return val === 1;
}

async function main() {
  const dbUrl = process.argv[2];
  if (!dbUrl) {
    console.error("Usage: npx ts-node scripts/migrate-from-mysql.ts <database-url>");
    console.error("");
    console.error("Examples:");
    console.error('  npx ts-node scripts/migrate-from-mysql.ts "mysql://user:pass@localhost/biatob"');
    console.error('  npx ts-node scripts/migrate-from-mysql.ts "sqlite:///path/to/db.sqlite"');
    process.exit(1);
  }

  let db: {
    query: <T>(sql: string) => Promise<T[]>;
    close: () => Promise<void>;
  };

  // Detect database type and create connection
  if (dbUrl.startsWith("sqlite:")) {
    const sqlitePath = dbUrl.replace("sqlite://", "");
    const Database = (await import("better-sqlite3")).default;
    const sqlite = new Database(sqlitePath, { readonly: true });
    db = {
      query: async <T>(sql: string): Promise<T[]> => {
        return sqlite.prepare(sql).all() as T[];
      },
      close: async () => {
        sqlite.close();
      },
    };
    console.log(`Connected to SQLite: ${sqlitePath}`);
  } else {
    const mysql = await import("mysql2/promise");
    const connection = await mysql.createConnection(dbUrl);
    db = {
      query: async <T>(sql: string): Promise<T[]> => {
        const [rows] = await connection.query(sql);
        return rows as T[];
      },
      close: async () => {
        await connection.end();
      },
    };
    console.log("Connected to MySQL");
  }

  try {
    // 1. Load passwords
    console.log("\nLoading passwords...");
    const passwords = await db.query<OldPassword>("SELECT * FROM passwords");
    const passwordMap = new Map<string, OldPassword>();
    for (const p of passwords) {
      passwordMap.set(p.password_id, p);
    }
    console.log(`  Found ${passwords.length} passwords`);

    // 2. Load and transform users
    console.log("\nLoading users...");
    const oldUsers = await db.query<OldUser>("SELECT * FROM users");
    console.log(`  Found ${oldUsers.length} users`);

    const users: Array<{
      _tempId: string;
      email: string;
      username: string;
      createdAt: number;
    }> = [];

    const legacyPasswordHashes: Array<{
      email: string;
      username: string;
      salt: string;
      scrypt: string;
    }> = [];

    for (let i = 0; i < oldUsers.length; i++) {
      const u = oldUsers[i];
      const tempId = generatePlaceholderId("user", i);
      userIdMap.set(u.username, tempId);

      users.push({
        _tempId: tempId,
        email: u.email_address.toLowerCase(),
        username: u.username,
        createdAt: Date.now(), // Will be updated if we have prediction creation times
      });

      // Get password hash for this user
      const pw = passwordMap.get(u.login_password_id);
      if (pw) {
        legacyPasswordHashes.push({
          email: u.email_address.toLowerCase(),
          username: u.username,
          salt: pw.salt.toString("base64"),
          scrypt: pw.scrypt.toString("base64"),
        });
      }
    }

    // 3. Load and transform predictions
    console.log("\nLoading predictions...");
    const oldPredictions = await db.query<OldPrediction>("SELECT * FROM predictions");
    console.log(`  Found ${oldPredictions.length} predictions`);

    const predictions: Array<{
      _tempId: string;
      predictionId: string;
      prediction: string;
      certaintyLowP: number;
      certaintyHighP: number;
      maximumStakeCents: number;
      createdAt: number;
      closesAt: number;
      resolvesAt: number;
      specialRules: string | undefined;
      creatorId: string;
      resolutionReminderSent: boolean;
      viewPrivacy: "public" | "link_only";
    }> = [];

    for (let i = 0; i < oldPredictions.length; i++) {
      const p = oldPredictions[i];
      const tempId = generatePlaceholderId("prediction", i);
      predictionIdMap.set(p.prediction_id, tempId);

      const creatorId = userIdMap.get(p.creator);
      if (!creatorId) {
        console.warn(`  Warning: Unknown creator "${p.creator}" for prediction "${p.prediction_id}"`);
        continue;
      }

      predictions.push({
        _tempId: tempId,
        predictionId: p.prediction_id,
        prediction: p.prediction,
        certaintyLowP: p.certainty_low_p,
        certaintyHighP: p.certainty_high_p,
        maximumStakeCents: p.maximum_stake_cents,
        createdAt: Math.floor(p.created_at_unixtime * 1000), // Convert to milliseconds
        closesAt: Math.floor(p.closes_at_unixtime * 1000),
        resolvesAt: Math.floor(p.resolves_at_unixtime * 1000),
        specialRules: p.special_rules || undefined,
        creatorId,
        resolutionReminderSent: toBool(p.resolution_reminder_sent),
        viewPrivacy: mapViewPrivacy(p.view_privacy),
      });
    }

    // 4. Load and transform trades
    console.log("\nLoading trades...");
    const oldTrades = await db.query<OldTrade>("SELECT * FROM trades");
    console.log(`  Found ${oldTrades.length} trades`);

    const trades: Array<{
      predictionId: string;
      bettorId: string;
      transactedAt: number;
      bettorIsSkeptic: boolean;
      bettorStakeCents: number;
      creatorStakeCents: number;
      state: "active" | "queued" | "disavowed" | "dequeue_failed";
      updatedAt: number;
      notes: string | undefined;
    }> = [];

    for (const t of oldTrades) {
      const predictionId = predictionIdMap.get(t.prediction_id);
      const bettorId = userIdMap.get(t.bettor);

      if (!predictionId) {
        console.warn(`  Warning: Unknown prediction "${t.prediction_id}" for trade`);
        continue;
      }
      if (!bettorId) {
        console.warn(`  Warning: Unknown bettor "${t.bettor}" for trade`);
        continue;
      }

      trades.push({
        predictionId,
        bettorId,
        transactedAt: Math.floor(t.transacted_at_unixtime * 1000),
        bettorIsSkeptic: toBool(t.bettor_is_a_skeptic),
        bettorStakeCents: t.bettor_stake_cents,
        creatorStakeCents: t.creator_stake_cents,
        state: mapTradeState(t.state),
        updatedAt: Math.floor(t.updated_at_unixtime * 1000),
        notes: t.notes || undefined,
      });
    }

    // 5. Load and transform resolutions
    console.log("\nLoading resolutions...");
    const oldResolutions = await db.query<OldResolution>("SELECT * FROM resolutions");
    console.log(`  Found ${oldResolutions.length} resolutions`);

    const resolutions: Array<{
      predictionId: string;
      resolvedAt: number;
      resolution: "none_yet" | "yes" | "no" | "invalid";
      notes: string | undefined;
    }> = [];

    for (const r of oldResolutions) {
      const predictionId = predictionIdMap.get(r.prediction_id);
      if (!predictionId) {
        console.warn(`  Warning: Unknown prediction "${r.prediction_id}" for resolution`);
        continue;
      }

      resolutions.push({
        predictionId,
        resolvedAt: Math.floor(r.resolved_at_unixtime * 1000),
        resolution: mapResolution(r.resolution),
        notes: r.notes || undefined,
      });
    }

    // 6. Load and transform prediction follows
    console.log("\nLoading prediction follows...");
    const oldFollows = await db.query<OldPredictionFollow>("SELECT * FROM prediction_follows");
    console.log(`  Found ${oldFollows.length} prediction follows`);

    const predictionFollows: Array<{
      predictionId: string;
      followerId: string;
    }> = [];

    for (const f of oldFollows) {
      const predictionId = predictionIdMap.get(f.prediction_id);
      const followerId = userIdMap.get(f.follower);

      if (!predictionId || !followerId) {
        continue;
      }

      predictionFollows.push({
        predictionId,
        followerId,
      });
    }

    // 7. Load and transform relationships
    console.log("\nLoading relationships...");
    const oldRelationships = await db.query<OldRelationship>("SELECT * FROM relationships");
    console.log(`  Found ${oldRelationships.length} relationships`);

    const relationships: Array<{
      subjectId: string;
      objectId: string;
      trusted: boolean;
    }> = [];

    for (const r of oldRelationships) {
      const subjectId = userIdMap.get(r.subject_username);
      const objectId = userIdMap.get(r.object_username);

      if (!subjectId || !objectId) {
        continue;
      }

      relationships.push({
        subjectId,
        objectId,
        trusted: toBool(r.trusted),
      });
    }

    // 8. Load and transform email invitations
    console.log("\nLoading email invitations...");
    const oldInvitations = await db.query<OldEmailInvitation>("SELECT * FROM email_invitations");
    console.log(`  Found ${oldInvitations.length} email invitations`);

    const emailInvitations: Array<{
      inviterId: string;
      recipientEmail: string;
      nonce: string;
      createdAt: number;
    }> = [];

    for (const inv of oldInvitations) {
      const inviterId = userIdMap.get(inv.inviter);
      // Note: In old schema, recipient is a username, not email
      // We need to look up the email
      const recipientUser = oldUsers.find((u) => u.username === inv.recipient);

      if (!inviterId) {
        console.warn(`  Warning: Unknown inviter "${inv.inviter}" for invitation`);
        continue;
      }

      emailInvitations.push({
        inviterId,
        recipientEmail: recipientUser?.email_address.toLowerCase() || inv.recipient,
        nonce: inv.nonce,
        createdAt: Date.now(), // Old schema doesn't have timestamp
      });
    }

    // Write output files
    console.log("\n--- Writing output files ---");
    writeJsonl("users.jsonl", users);
    writeJsonl("legacyPasswordHashes.jsonl", legacyPasswordHashes);
    writeJsonl("predictions.jsonl", predictions);
    writeJsonl("trades.jsonl", trades);
    writeJsonl("resolutions.jsonl", resolutions);
    writeJsonl("predictionFollows.jsonl", predictionFollows);
    writeJsonl("relationships.jsonl", relationships);
    writeJsonl("emailInvitations.jsonl", emailInvitations);

    // Write ID mapping for import script reference
    const idMapping = {
      users: Object.fromEntries(userIdMap),
      predictions: Object.fromEntries(predictionIdMap),
    };
    fs.writeFileSync(
      path.join(process.cwd(), "migration-output", "id-mapping.json"),
      JSON.stringify(idMapping, null, 2)
    );
    console.log("\nWrote id-mapping.json");

    console.log("\n✓ Migration export complete!");
    console.log("\nNext steps:");
    console.log("1. Review the JSONL files in ./migration-output/");
    console.log("2. Use Convex's bulk import or a custom import script to load the data");
    console.log("3. The _tempId fields and ID references will need to be resolved during import");
  } finally {
    await db.close();
  }
}

main().catch((err) => {
  console.error("Migration failed:", err);
  process.exit(1);
});
