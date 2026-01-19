# TODO

## Completed

### Switch to Convex Auth
Replaced the homebrewed HMAC token scheme with [Convex Auth](https://docs.convex.dev/auth):
- `convex/auth.ts` - Now uses `convexAuth()` with Password provider
- `convex/http.ts` - Added HTTP routes for auth
- `lib/auth.tsx` - Uses `useConvexAuth()` hooks
- All mutations/queries now use `auth.getUserId(ctx)` instead of token validation

### Tests
Added comprehensive test suite using Vitest and convex-test:
- `convex/auth.test.ts` - Authentication tests
- `convex/predictions.test.ts` - Prediction CRUD and resolution tests
- `convex/trades.test.ts` - Betting/staking tests
- `convex/relationships.test.ts` - Trust and invitation tests
- `lib/utils.test.ts` - Utility and phase calculation tests

### Email Templates
Added styled React Email components with Resend integration:
- `emails/components/EmailLayout.tsx` - Shared layout component
- `emails/VerificationEmail.tsx` - Verification code email
- `emails/InvitationEmail.tsx` - Trust invitation email
- `emails/ResolutionNotificationEmail.tsx` - Prediction resolved notification
- `emails/ResolutionReminderEmail.tsx` - Reminder to resolve prediction
- `convex/email.ts` - Updated to render React Email components

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
