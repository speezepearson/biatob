# TODO

## High Priority

### Switch to Convex Auth
The current authentication implementation uses a homebrewed HMAC token scheme with manual session management. This should be replaced with [Convex Auth](https://docs.convex.dev/auth) which provides:
- Built-in session management
- OAuth providers (Google, GitHub, etc.)
- Email/password authentication
- Secure token handling without manual HMAC signing

Files to refactor:
- `convex/auth.ts` - Replace with Convex Auth configuration
- `convex/schema.ts` - Remove `sessions`, `emailVerifications` tables
- `lib/auth.tsx` - Use Convex Auth React hooks
- All pages using `token` prop - Switch to Convex Auth's `useConvexAuth()`

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

### Tests
No test suite exists. Should add:
- Unit tests for utility functions (`lib/utils.ts`)
- Integration tests for Convex functions
- E2E tests with Playwright or Cypress

## Low Priority

### Email Templates
Current email notifications are plain text. The original had styled HTML templates via Jinja2. Consider:
- Using React Email for component-based email templates
- Adding proper HTML styling to match app branding

### Fast Bet Page
The original had a dedicated "Fast Bet" page for quick betting. Currently this functionality is only available on the prediction detail page. Could add a streamlined betting interface.
