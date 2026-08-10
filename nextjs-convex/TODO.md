# TODO

## Completed

### Switch to Convex Auth
Replaced the homebrewed HMAC token scheme with [Convex Auth](https://docs.convex.dev/auth):
- `convex/auth.ts` - Now uses `convexAuth()` with Password provider
- `convex/http.ts` - Added HTTP routes for auth
- `lib/auth.tsx` - Uses `useConvexAuth()` hooks
- All mutations/queries now use `auth.getUserId(ctx)` instead of token validation

### Email Templates
Added styled React Email components with Resend integration:
- `emails/components/EmailLayout.tsx` - Shared layout component
- `emails/VerificationEmail.tsx` - Verification code email
- `emails/InvitationEmail.tsx` - Trust invitation email
- `emails/ResolutionNotificationEmail.tsx` - Prediction resolved notification
- `emails/ResolutionReminderEmail.tsx` - Reminder to resolve prediction
- `convex/email.ts` - Updated to render React Email components

### Test Infrastructure
Set up test infrastructure with Vitest and convex-test:
- `vitest.config.ts` - Test configuration
- `convex/testHelpers.ts` - Test utilities and helpers
- `convex/testSchema.ts` - Schema for testing (without Convex Auth tables)
- `lib/utils.test.ts` - Utility function tests (49 tests, all passing)

### Convex Function Tests
Rewrote all Convex function tests using `convex-test` with `t.withIdentity()` for auth mocking:
- `convex/predictions.test.ts` - 14 tests for prediction CRUD operations
- `convex/trades.test.ts` - 12 tests for staking and disavowing
- `convex/relationships.test.ts` - 16 tests for trust and invitations

All 91 tests passing. Auth is mocked by creating users directly in the database and using `t.withIdentity({ subject: \`${userId}|test-session\` })`.

### GitHub Actions
Added CI workflow (`.github/workflows/test.yml`) that runs tests on PRs and pushes to main.

### Data Migration & Legacy Auth
Created migration infrastructure for moving users from the old MySQL/SQLite database:

**Schema additions:**
- `legacyPasswordHashes` table - stores old scrypt hashes for lazy migration

**Auth improvements:**
- Custom `crypto` in Password provider with self-describing hash format: `scrypt$N=16384,r=8,p=1,dkLen=64$<salt>$<hash>`
- Parameters pinned to prevent breakage on library updates
- `signInWithLegacyMigration` action for transparent user migration on first sign-in
- Cryptographically secure nonce/ID generation using `crypto.getRandomValues()`

**Migration script:**
- `scripts/migrate-from-mysql.ts` - exports MySQL/SQLite data to JSONL files
- Outputs: users.jsonl, legacyPasswordHashes.jsonl, predictions.jsonl, trades.jsonl, resolutions.jsonl, predictionFollows.jsonl, relationships.jsonl, emailInvitations.jsonl

## Medium Priority

### OG Image Generation
The original app generated social media preview images using PIL/Pillow showing prediction details. This is missing from the rewrite. Options:
- Use Vercel OG (`@vercel/og`) for edge-generated images
- Create a Convex HTTP action that generates images
- Use a third-party service like Cloudinary

## Low Priority

### Fast Bet Page
The original had a dedicated "Fast Bet" page for quick betting. Currently this functionality is only available on the prediction detail page. Could add a streamlined betting interface.
