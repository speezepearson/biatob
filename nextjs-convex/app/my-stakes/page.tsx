"use client";

import Link from "next/link";
import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api";
import { useAuth } from "@/lib/auth";
import {
  formatCents,
  formatProbability,
  formatDate,
  formatRelativeTime,
  getResolutionText,
  getResolutionColorClass,
  isBettingOpen,
} from "@/lib/utils";

export default function MyStakesPage() {
  const { user, token, isLoading: authLoading } = useAuth();

  const stakes = useQuery(
    api.predictions.listMyStakes,
    token ? { token } : "skip"
  );

  if (authLoading) {
    return <div className="text-center text-gray-500">Loading...</div>;
  }

  if (!user || !token) {
    return (
      <div className="card text-center">
        <p className="text-gray-600">Please log in to view your stakes.</p>
        <Link href="/login" className="link">
          Log in
        </Link>
      </div>
    );
  }

  if (stakes === undefined) {
    return <div className="text-center text-gray-500">Loading stakes...</div>;
  }

  // Separate into created and bet-on predictions
  const myPredictions = stakes.filter((s) => s.isCreator);
  const myBets = stakes.filter((s) => !s.isCreator);

  // Further categorize
  const activePredictions = myPredictions.filter(
    (p) => !p.resolution || p.resolution.resolution === "none_yet"
  );
  const resolvedPredictions = myPredictions.filter(
    (p) => p.resolution && p.resolution.resolution !== "none_yet"
  );

  const activeBets = myBets.filter(
    (p) => !p.resolution || p.resolution.resolution === "none_yet"
  );
  const resolvedBets = myBets.filter(
    (p) => p.resolution && p.resolution.resolution !== "none_yet"
  );

  return (
    <div className="space-y-8">
      <h1 className="text-2xl font-bold">My Stakes</h1>

      {/* My Predictions */}
      <div>
        <h2 className="text-xl font-semibold mb-4">Predictions I Created</h2>

        {myPredictions.length === 0 ? (
          <div className="card text-center">
            <p className="text-gray-600 mb-4">You haven&apos;t created any predictions yet.</p>
            <Link href="/predictions/new" className="btn-primary">
              Create a Prediction
            </Link>
          </div>
        ) : (
          <>
            {activePredictions.length > 0 && (
              <div className="mb-6">
                <h3 className="text-lg font-medium text-gray-700 mb-3">Active</h3>
                <div className="space-y-3">
                  {activePredictions.map((prediction) => (
                    <PredictionCard
                      key={prediction._id}
                      prediction={prediction}
                      showCreator={false}
                    />
                  ))}
                </div>
              </div>
            )}

            {resolvedPredictions.length > 0 && (
              <div>
                <h3 className="text-lg font-medium text-gray-700 mb-3">Resolved</h3>
                <div className="space-y-3">
                  {resolvedPredictions.map((prediction) => (
                    <PredictionCard
                      key={prediction._id}
                      prediction={prediction}
                      showCreator={false}
                    />
                  ))}
                </div>
              </div>
            )}
          </>
        )}
      </div>

      {/* My Bets */}
      <div>
        <h2 className="text-xl font-semibold mb-4">Predictions I Bet On</h2>

        {myBets.length === 0 ? (
          <div className="card">
            <p className="text-gray-600">You haven&apos;t placed any bets yet.</p>
          </div>
        ) : (
          <>
            {activeBets.length > 0 && (
              <div className="mb-6">
                <h3 className="text-lg font-medium text-gray-700 mb-3">Active</h3>
                <div className="space-y-3">
                  {activeBets.map((prediction) => (
                    <PredictionCard
                      key={prediction._id}
                      prediction={prediction}
                      showCreator={true}
                      showMyBets={true}
                    />
                  ))}
                </div>
              </div>
            )}

            {resolvedBets.length > 0 && (
              <div>
                <h3 className="text-lg font-medium text-gray-700 mb-3">Resolved</h3>
                <div className="space-y-3">
                  {resolvedBets.map((prediction) => (
                    <PredictionCard
                      key={prediction._id}
                      prediction={prediction}
                      showCreator={true}
                      showMyBets={true}
                    />
                  ))}
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}

function PredictionCard({
  prediction,
  showCreator = true,
  showMyBets = false,
}: {
  prediction: any;
  showCreator?: boolean;
  showMyBets?: boolean;
}) {
  const isOpen = isBettingOpen(prediction.closesAt);
  const resolution = prediction.resolution?.resolution ?? null;

  return (
    <Link
      href={`/p/${prediction.predictionId}`}
      className="card block hover:shadow-md transition-shadow"
    >
      <div className="flex justify-between items-start">
        <div className="flex-1">
          <p className="font-medium text-gray-900 mb-1">{prediction.prediction}</p>
          <div className="text-sm text-gray-500 space-x-2">
            {showCreator && <span>by {prediction.creatorUsername}</span>}
            <span>
              {formatProbability(prediction.certaintyLowP)}-
              {formatProbability(prediction.certaintyHighP)}
            </span>
            {isOpen ? (
              <span className="text-green-600">Betting open</span>
            ) : (
              <span className="text-gray-400">Betting closed</span>
            )}
          </div>
        </div>
        <div className="text-right ml-4">
          <span
            className={`text-sm font-medium ${getResolutionColorClass(resolution)}`}
          >
            {getResolutionText(resolution)}
          </span>
          <p className="text-xs text-gray-400 mt-1">
            Resolves {formatRelativeTime(prediction.resolvesAt)}
          </p>
        </div>
      </div>

      {showMyBets && prediction.myTrades && prediction.myTrades.length > 0 && (
        <div className="mt-3 pt-3 border-t">
          <p className="text-xs text-gray-500 mb-2">Your bets:</p>
          <div className="flex flex-wrap gap-2">
            {prediction.myTrades.map((trade: any) => (
              <span
                key={trade._id}
                className={`text-xs px-2 py-1 rounded ${
                  trade.bettorIsSkeptic
                    ? "bg-red-100 text-red-700"
                    : "bg-green-100 text-green-700"
                }`}
              >
                {trade.bettorIsSkeptic ? "NO" : "YES"}{" "}
                {formatCents(trade.bettorStakeCents)} vs{" "}
                {formatCents(trade.creatorStakeCents)}
              </span>
            ))}
          </div>
        </div>
      )}
    </Link>
  );
}
