"use client";

import Link from "next/link";
import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api";
import { useAuth } from "@/lib/auth";
import { formatDate, formatProbability, getResolutionText, getResolutionColorClass } from "@/lib/utils";

export default function HomePage() {
  const { user } = useAuth();
  const publicPredictions = useQuery(api.predictions.listPublic, { limit: 20 });

  return (
    <div className="space-y-8">
      {/* Hero section */}
      <div className="text-center py-8">
        <h1 className="text-4xl font-bold text-gray-900 mb-4">
          Bet I Am The Only Bettor
        </h1>
        <p className="text-xl text-gray-600 max-w-2xl mx-auto mb-6">
          Make predictions, stake your reputation, and see how well-calibrated you really are.
          Honor-based prediction markets for friends and trusted connections.
        </p>
        {!user && (
          <div className="flex justify-center space-x-4">
            <Link href="/signup" className="btn-primary">
              Get Started
            </Link>
            <Link href="/login" className="btn-secondary">
              Log In
            </Link>
          </div>
        )}
        {user && (
          <Link href="/predictions/new" className="btn-primary">
            Create a Prediction
          </Link>
        )}
      </div>

      {/* How it works */}
      <div className="card">
        <h2 className="text-2xl font-bold mb-4">How It Works</h2>
        <div className="grid md:grid-cols-3 gap-6">
          <div>
            <div className="text-3xl mb-2">1</div>
            <h3 className="font-semibold mb-2">Make a Prediction</h3>
            <p className="text-gray-600">
              State what you believe will happen and your confidence level (e.g., 70-80% likely).
            </p>
          </div>
          <div>
            <div className="text-3xl mb-2">2</div>
            <h3 className="font-semibold mb-2">Accept Bets</h3>
            <p className="text-gray-600">
              Others can bet against (or with) your prediction at odds implied by your confidence.
            </p>
          </div>
          <div>
            <div className="text-3xl mb-2">3</div>
            <h3 className="font-semibold mb-2">Resolve & Settle</h3>
            <p className="text-gray-600">
              When the outcome is known, resolve the prediction and settle bets on your honor.
            </p>
          </div>
        </div>
      </div>

      {/* Public predictions */}
      <div>
        <h2 className="text-2xl font-bold mb-4">Recent Public Predictions</h2>
        {publicPredictions === undefined ? (
          <div className="text-gray-500">Loading...</div>
        ) : publicPredictions.length === 0 ? (
          <div className="text-gray-500">No public predictions yet.</div>
        ) : (
          <div className="space-y-4">
            {publicPredictions.map((prediction) => (
              <Link
                key={prediction._id}
                href={`/p/${prediction.predictionId}`}
                className="card block hover:shadow-md transition-shadow"
              >
                <div className="flex justify-between items-start">
                  <div className="flex-1">
                    <p className="font-medium text-gray-900 mb-1">
                      {prediction.prediction}
                    </p>
                    <p className="text-sm text-gray-500">
                      by {prediction.creatorUsername} &middot;{" "}
                      {formatProbability(prediction.certaintyLowP)}-
                      {formatProbability(prediction.certaintyHighP)} confident
                    </p>
                  </div>
                  <div className="text-right ml-4">
                    <span
                      className={`text-sm font-medium ${getResolutionColorClass(
                        prediction.resolution?.resolution ?? null
                      )}`}
                    >
                      {getResolutionText(prediction.resolution?.resolution ?? null)}
                    </span>
                    <p className="text-xs text-gray-400 mt-1">
                      Resolves {formatDate(prediction.resolvesAt)}
                    </p>
                  </div>
                </div>
              </Link>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
