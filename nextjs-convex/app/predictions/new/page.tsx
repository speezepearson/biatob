"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useMutation } from "convex/react";
import { api } from "@/convex/_generated/api";
import { useAuth } from "@/lib/auth";

export default function CreatePredictionPage() {
  const router = useRouter();
  const { user, token } = useAuth();
  const createPrediction = useMutation(api.predictions.create);

  const [prediction, setPrediction] = useState("");
  const [certaintyLow, setCertaintyLow] = useState(60);
  const [certaintyHigh, setCertaintyHigh] = useState(80);
  const [maxStakeDollars, setMaxStakeDollars] = useState(100);
  const [closesIn, setClosesIn] = useState(30); // days
  const [resolvesIn, setResolvesIn] = useState(30); // days
  const [specialRules, setSpecialRules] = useState("");
  const [viewPrivacy, setViewPrivacy] = useState<"public" | "link_only">("public");
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  if (!user || !token) {
    return (
      <div className="card text-center">
        <p className="text-gray-600">Please log in to create a prediction.</p>
      </div>
    );
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (certaintyLow > certaintyHigh) {
      setError("Lower confidence bound must be less than or equal to upper bound");
      return;
    }

    if (prediction.trim().length < 10) {
      setError("Prediction must be at least 10 characters");
      return;
    }

    setIsLoading(true);

    const now = Date.now();
    const closesAt = now + closesIn * 24 * 60 * 60 * 1000;
    const resolvesAt = now + resolvesIn * 24 * 60 * 60 * 1000;

    try {
      const result = await createPrediction({
        token,
        prediction: prediction.trim(),
        certaintyLowP: certaintyLow / 100,
        certaintyHighP: certaintyHigh / 100,
        maximumStakeCents: Math.round(maxStakeDollars * 100),
        closesAt,
        resolvesAt,
        specialRules: specialRules.trim() || undefined,
        viewPrivacy,
      });

      router.push(`/p/${result.predictionId}`);
    } catch (err: any) {
      setError(err.message || "Failed to create prediction");
    } finally {
      setIsLoading(false);
    }
  };

  const midProbability = (certaintyLow + certaintyHigh) / 2 / 100;
  const skepticOdds = midProbability / (1 - midProbability);
  const believerOdds = (1 - midProbability) / midProbability;

  return (
    <div className="max-w-2xl mx-auto">
      <h1 className="text-2xl font-bold mb-6">Create a Prediction</h1>

      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded mb-4">
          {error}
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="card">
          <h2 className="text-lg font-semibold mb-4">What do you predict?</h2>

          <div>
            <label htmlFor="prediction" className="label">
              Prediction Statement
            </label>
            <textarea
              id="prediction"
              value={prediction}
              onChange={(e) => setPrediction(e.target.value)}
              className="input min-h-[100px]"
              placeholder="e.g., The next iPhone will have USB-C"
              required
              maxLength={1024}
            />
            <p className="mt-1 text-sm text-gray-500">
              {prediction.length}/1024 characters
            </p>
          </div>
        </div>

        <div className="card">
          <h2 className="text-lg font-semibold mb-4">How confident are you?</h2>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label htmlFor="certaintyLow" className="label">
                Lower Bound (%)
              </label>
              <input
                type="number"
                id="certaintyLow"
                value={certaintyLow}
                onChange={(e) => setCertaintyLow(Number(e.target.value))}
                className="input"
                min={1}
                max={99}
                required
              />
            </div>
            <div>
              <label htmlFor="certaintyHigh" className="label">
                Upper Bound (%)
              </label>
              <input
                type="number"
                id="certaintyHigh"
                value={certaintyHigh}
                onChange={(e) => setCertaintyHigh(Number(e.target.value))}
                className="input"
                min={1}
                max={99}
                required
              />
            </div>
          </div>

          <p className="mt-2 text-sm text-gray-600">
            You believe this prediction is{" "}
            <strong>{certaintyLow}%-{certaintyHigh}%</strong> likely to be true.
          </p>

          <div className="mt-4 p-3 bg-gray-50 rounded text-sm">
            <p className="font-medium mb-2">Implied odds (at {(midProbability * 100).toFixed(0)}% midpoint):</p>
            <ul className="space-y-1 text-gray-600">
              <li>
                Skeptics bet $1 to win ${skepticOdds.toFixed(2)} if NO
              </li>
              <li>
                Believers bet $1 to win ${believerOdds.toFixed(2)} if YES
              </li>
            </ul>
          </div>
        </div>

        <div className="card">
          <h2 className="text-lg font-semibold mb-4">Stake Limits</h2>

          <div>
            <label htmlFor="maxStake" className="label">
              Maximum Stake ($)
            </label>
            <input
              type="number"
              id="maxStake"
              value={maxStakeDollars}
              onChange={(e) => setMaxStakeDollars(Number(e.target.value))}
              className="input"
              min={1}
              required
            />
            <p className="mt-1 text-sm text-gray-500">
              The most you&apos;re willing to put at risk on each side.
            </p>
          </div>
        </div>

        <div className="card">
          <h2 className="text-lg font-semibold mb-4">Timeline</h2>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label htmlFor="closesIn" className="label">
                Betting Closes In (days)
              </label>
              <input
                type="number"
                id="closesIn"
                value={closesIn}
                onChange={(e) => setClosesIn(Number(e.target.value))}
                className="input"
                min={1}
                required
              />
            </div>
            <div>
              <label htmlFor="resolvesIn" className="label">
                Expected Resolution In (days)
              </label>
              <input
                type="number"
                id="resolvesIn"
                value={resolvesIn}
                onChange={(e) => setResolvesIn(Number(e.target.value))}
                className="input"
                min={1}
                required
              />
            </div>
          </div>
        </div>

        <div className="card">
          <h2 className="text-lg font-semibold mb-4">Additional Options</h2>

          <div className="space-y-4">
            <div>
              <label htmlFor="specialRules" className="label">
                Special Rules (optional)
              </label>
              <textarea
                id="specialRules"
                value={specialRules}
                onChange={(e) => setSpecialRules(e.target.value)}
                className="input min-h-[80px]"
                placeholder="Any qualifications or special conditions..."
              />
            </div>

            <div>
              <label className="label">Visibility</label>
              <div className="space-y-2">
                <label className="flex items-center">
                  <input
                    type="radio"
                    name="privacy"
                    value="public"
                    checked={viewPrivacy === "public"}
                    onChange={() => setViewPrivacy("public")}
                    className="mr-2"
                  />
                  <span>Public (anyone can see and bet)</span>
                </label>
                <label className="flex items-center">
                  <input
                    type="radio"
                    name="privacy"
                    value="link_only"
                    checked={viewPrivacy === "link_only"}
                    onChange={() => setViewPrivacy("link_only")}
                    className="mr-2"
                  />
                  <span>Link only (only people with the link can see)</span>
                </label>
              </div>
            </div>
          </div>
        </div>

        <button
          type="submit"
          disabled={isLoading}
          className="btn-primary w-full"
        >
          {isLoading ? "Creating..." : "Create Prediction"}
        </button>
      </form>
    </div>
  );
}
