# BIATOB - Bet I Am The Only Bettor

A prediction market app built with Next.js and Convex. Make predictions, stake your reputation, and see how well-calibrated you really are.

## Features

- **Create Predictions**: State what you believe will happen and your confidence level
- **Honor-Based Betting**: Others can bet against (or with) your predictions
- **Trust Relationships**: Build a network of trusted friends for betting
- **Resolution Tracking**: Resolve predictions and settle bets on your honor
- **Email Notifications**: Get notified about resolutions and reminders

## Tech Stack

- **Frontend**: Next.js 14 with React 18 and TypeScript
- **Backend**: Convex (serverless database and functions)
- **Styling**: Tailwind CSS
- **Email**: Resend (optional)

## Getting Started

### Prerequisites

- Node.js 18+
- npm or yarn
- A Convex account (free at [convex.dev](https://convex.dev))

### Setup

1. **Install dependencies**:
   ```bash
   cd nextjs-convex
   npm install
   ```

2. **Set up Convex**:
   ```bash
   npx convex dev
   ```
   This will prompt you to log in and create a new project.

3. **Configure environment**:
   Copy `.env.local.example` to `.env.local`:
   ```bash
   cp .env.local.example .env.local
   ```
   Update `NEXT_PUBLIC_CONVEX_URL` with your Convex deployment URL.

4. **Run the development server**:
   ```bash
   npm run dev
   ```
   This runs both Next.js and Convex in development mode.

5. Open [http://localhost:3000](http://localhost:3000)

### Email Setup (Optional)

To enable email notifications:

1. Create a [Resend](https://resend.com) account
2. In the Convex Dashboard, go to Settings > Environment Variables
3. Add:
   - `RESEND_API_KEY`: Your Resend API key
   - `EMAIL_FROM`: Your sender address (e.g., `BIATOB <noreply@yourdomain.com>`)
   - `BASE_URL`: Your production URL (e.g., `https://biatob.com`)

## Project Structure

```
nextjs-convex/
├── app/                    # Next.js App Router pages
│   ├── page.tsx           # Home page
│   ├── login/             # Login page
│   ├── signup/            # Signup page
│   ├── predictions/new/   # Create prediction
│   ├── p/[predictionId]/  # Prediction detail
│   ├── my-stakes/         # User's stakes
│   ├── user/[username]/   # User profile
│   ├── settings/          # User settings
│   └── invite/[nonce]/    # Accept invitation
├── components/            # React components
│   └── Navbar.tsx
├── lib/                   # Utilities
│   ├── auth.tsx          # Auth context
│   └── utils.ts          # Helper functions
├── convex/               # Convex backend
│   ├── schema.ts         # Database schema
│   ├── auth.ts           # Auth functions
│   ├── predictions.ts    # Prediction functions
│   ├── trades.ts         # Trading functions
│   ├── relationships.ts  # Trust relationships
│   ├── email.ts          # Email actions
│   ├── scheduled.ts      # Scheduled tasks
│   └── crons.ts          # Cron jobs
└── ...config files
```

## How It Works

### Creating a Prediction

1. Specify what you predict will happen
2. Set your confidence range (e.g., 60-80%)
3. Set maximum stake amount
4. Choose when betting closes and when to resolve

### Betting

- **Believers** bet that the prediction will come true (YES)
- **Skeptics** bet against the prediction (NO)
- Odds are calculated from the creator's confidence level
- Example: At 75% confidence, skeptics bet $1 to win $3 (if NO)

### Resolution

- Only the creator can resolve their prediction
- Options: YES, NO, or INVALID
- All followers receive email notifications

### Trust System

- Invite friends to establish mutual trust
- Trust relationships enable betting between users
- View who trusts you and who you trust

## Deployment

### Vercel (Recommended)

1. Push to GitHub
2. Import project to Vercel
3. Add environment variable: `NEXT_PUBLIC_CONVEX_URL`
4. Deploy!

### Convex

Convex automatically deploys when you run `npx convex deploy`.

## License

MIT
