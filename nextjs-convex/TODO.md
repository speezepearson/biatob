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

## High Priority

### Convex Function Tests
The Convex function tests (`*.test.ts.skip`) were written for the old token-based auth system and need to be rewritten for Convex Auth:
- `convex/auth.test.ts.skip` - Auth tests need complete rewrite for Convex Auth
- `convex/predictions.test.ts.skip` - Needs auth context mocking
- `convex/trades.test.ts.skip` - Needs auth context mocking
- `convex/relationships.test.ts.skip` - Needs auth context mocking

The tests require:
1. Mocking `auth.getUserId(ctx)` to return test user IDs
2. Setting up test users directly in the database rather than through auth functions
3. Potentially using Convex Auth's testing utilities when available

## Medium Priority

### Data Migration
No migration script exists for moving data from the old MySQL/SQLite database to Convex. Need to create a one-time migration script that:
- Exports users, predictions, trades, resolutions, relationships from old DB
- Transforms data to match new Convex schema
- Imports into Convex via mutation or bulk import

### OG Image Generation
The original app generated social media preview images using PIL/Pillow showing prediction details. This is missing from the rewrite. Options:
- Use Vercel OG (`@vercel/og`) for edge-generated images
- Create a Convex HTTP action that generates images
- Use a third-party service like Cloudinary

## Low Priority

### Fast Bet Page
The original had a dedicated "Fast Bet" page for quick betting. Currently this functionality is only available on the prediction detail page. Could add a streamlined betting interface.
