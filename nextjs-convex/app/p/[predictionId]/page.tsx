"use client";

import { useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { useQuery, useMutation } from "convex/react";
import { api } from "@/convex/_generated/api";
import { useAuth } from "@/lib/auth";
import {
  formatCents,
  formatProbability,
  formatDate,
  formatDateTime,
  formatRelativeTime,
  isBettingOpen,
  getResolutionText,
  getResolutionColorClass,
} from "@/lib/utils";

export default function PredictionPage() {
  const params = useParams();
  const predictionId = params.predictionId as string;
  const { user, token } = useAuth();

  const prediction = useQuery(api.predictions.getByPredictionId, {
    predictionId,
    token: token ?? undefined,
  });

  const stakeMutation = useMutation(api.trades.stake);
  const resolveMutation = useMutation(api.predictions.resolve);
  const followMutation = useMutation(api.predictions.setFollowing);

  const [stakeAmount, setStakeAmount] = useState(10);
  const [stakeNotes, setStakeNotes] = useState("");
  const [stakeError, setStakeError] = useState<string | null>(null);
  const [isStaking, setIsStaking] = useState(false);

  const [resolution, setResolution] = useState<"yes" | "no" | "invalid">("yes");
  const [resolveNotes, setResolveNotes] = useState("");
  const [resolveError, setResolveError] = useState<string | null>(null);
  const [isResolving, setIsResolving] = useState(false);

  if (prediction === undefined) {
    return <div className="text-center text-gray-500">Loading...</div>;
  }

  if (prediction === null) {
    return (
      <div className="card text-center">
        <h1 className="text-2xl font-bold text-gray-900 mb-2">Prediction Not Found</h1>
        <p className="text-gray-600">This prediction doesn&apos;t exist or you don&apos;t have access to it.</p>
      </div>
    );
  }

  const isCreator = user && prediction.creatorId === user._id;
  const canBet = user && !isCreator && isBettingOpen(prediction.closesAt) && !prediction.resolution?.resolution;
  const canResolve = isCreator && (!prediction.resolution || prediction.resolution.resolution === "none_yet");
  const midP = (prediction.certaintyLowP + prediction.certaintyHighP) / 2;

  const handleStake = async (isSkeptic: boolean) => {
    if (!token) return;
    setStakeError(null);
    setIsStaking(true);

    try {
      await stakeMutation({
        token,
        predictionId,
        bettorIsSkeptic: isSkeptic,
        bettorStakeCents: Math.round(stakeAmount * 100),
        notes: stakeNotes || undefined,
      });
      setStakeAmount(10);
      setStakeNotes("");
    } catch (err: any) {
      setStakeError(err.message || "Failed to place bet");
    } finally {
      setIsStaking(false);
    }
  };

  const handleResolve = async () => {
    if (!token) return;
    setResolveError(null);
    setIsResolving(true);

    try {
      await resolveMutation({
        token,
        predictionId,
        resolution,
        notes: resolveNotes || undefined,
      });
    } catch (err: any) {
      setResolveError(err.message || "Failed to resolve prediction");
    } finally {
      setIsResolving(false);
    }
  };

  const handleToggleFollow = async () => {
    if (!token) return;
    await followMutation({
      token,
      predictionId,
      following: !prediction.isFollowing,
    });
  };

  // Calculate potential winnings
  const skepticWinnings = stakeAmount * (midP / (1 - midP));
  const believerWinnings = stakeAmount * ((1 - midP) / midP);

  return (
    <div className="space-y-6">
      {/* Main prediction card */}
      <div className="card">
        <div className="flex justify-between items-start mb-4">
          <div>
            <h1 className="text-2xl font-bold text-gray-900 mb-2">
              {prediction.prediction}
            </h1>
            <p className="text-gray-600">
              Created by{" "}
              <Link href={`/user/${prediction.creatorUsername}`} className="link">
                {prediction.creatorUsername}
              </Link>
              {" "}&middot; {formatDate(prediction.createdAt)}
            </p>
          </div>
          <div className="text-right">
            <span
              className={`text-lg font-semibold ${getResolutionColorClass(
                prediction.resolution?.resolution ?? null
              )}`}
            >
              {getResolutionText(prediction.resolution?.resolution ?? null)}
            </span>
          </div>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 py-4 border-y">
          <div>
            <p className="text-sm text-gray-500">Confidence</p>
            <p className="font-semibold">
              {formatProbability(prediction.certaintyLowP)}-
              {formatProbability(prediction.certaintyHighP)}
            </p>
          </div>
          <div>
            <p className="text-sm text-gray-500">Max Stake</p>
            <p className="font-semibold">{formatCents(prediction.maximumStakeCents)}</p>
          </div>
          <div>
            <p className="text-sm text-gray-500">Betting Closes</p>
            <p className="font-semibold">{formatRelativeTime(prediction.closesAt)}</p>
          </div>
          <div>
            <p className="text-sm text-gray-500">Resolves</p>
            <p className="font-semibold">{formatRelativeTime(prediction.resolvesAt)}</p>
          </div>
        </div>

        {prediction.specialRules && (
          <div className="mt-4 p-3 bg-yellow-50 rounded">
            <p className="text-sm font-medium text-yellow-800">Special Rules:</p>
            <p className="text-sm text-yellow-700">{prediction.specialRules}</p>
          </div>
        )}

        {user && (
          <div className="mt-4 flex items-center space-x-4">
            <button
              onClick={handleToggleFollow}
              className={prediction.isFollowing ? "btn-secondary" : "btn-primary"}
            >
              {prediction.isFollowing ? "Unfollow" : "Follow"}
            </button>
            <button
              onClick={() => navigator.clipboard.writeText(window.location.href)}
              className="btn-secondary"
            >
              Copy Link
            </button>
          </div>
        )}
      </div>

      {/* Stakes summary */}
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Current Stakes</h2>
        <div className="grid grid-cols-2 gap-4">
          <div className="p-4 bg-green-50 rounded">
            <p className="text-sm text-green-700">Believers (YES)</p>
            <p className="text-xl font-bold text-green-800">
              {formatCents(prediction.believerStakes)}
            </p>
            <p className="text-xs text-green-600">
              Creator at risk: {formatCents(prediction.creatorStakesForBelievers)}
            </p>
            <p className="text-xs text-green-600">
              Remaining: {formatCents(prediction.remainingBelieverStakes)}
            </p>
          </div>
          <div className="p-4 bg-red-50 rounded">
            <p className="text-sm text-red-700">Skeptics (NO)</p>
            <p className="text-xl font-bold text-red-800">
              {formatCents(prediction.skepticStakes)}
            </p>
            <p className="text-xs text-red-600">
              Creator at risk: {formatCents(prediction.creatorStakesForSkeptics)}
            </p>
            <p className="text-xs text-red-600">
              Remaining: {formatCents(prediction.remainingSkepticStakes)}
            </p>
          </div>
        </div>
      </div>

      {/* Betting form */}
      {canBet && (
        <div className="card">
          <h2 className="text-lg font-semibold mb-4">Place a Bet</h2>

          {stakeError && (
            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded mb-4">
              {stakeError}
            </div>
          )}

          <div className="space-y-4">
            <div>
              <label htmlFor="stakeAmount" className="label">
                Your Stake ($)
              </label>
              <input
                type="number"
                id="stakeAmount"
                value={stakeAmount}
                onChange={(e) => setStakeAmount(Number(e.target.value))}
                className="input"
                min={1}
              />
            </div>

            <div>
              <label htmlFor="stakeNotes" className="label">
                Notes (optional)
              </label>
              <input
                type="text"
                id="stakeNotes"
                value={stakeNotes}
                onChange={(e) => setStakeNotes(e.target.value)}
                className="input"
                placeholder="Any notes about your bet..."
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <button
                onClick={() => handleStake(false)}
                disabled={isStaking}
                className="btn-success py-4"
              >
                <div>
                  <div className="font-bold">Bet YES</div>
                  <div className="text-sm opacity-90">
                    Win ${believerWinnings.toFixed(2)} if true
                  </div>
                </div>
              </button>
              <button
                onClick={() => handleStake(true)}
                disabled={isStaking}
                className="btn-danger py-4"
              >
                <div>
                  <div className="font-bold">Bet NO</div>
                  <div className="text-sm opacity-90">
                    Win ${skepticWinnings.toFixed(2)} if false
                  </div>
                </div>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Resolution form */}
      {canResolve && (
        <div className="card">
          <h2 className="text-lg font-semibold mb-4">Resolve Prediction</h2>

          {resolveError && (
            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded mb-4">
              {resolveError}
            </div>
          )}

          <div className="space-y-4">
            <div>
              <label className="label">Resolution</label>
              <div className="flex space-x-4">
                <label className="flex items-center">
                  <input
                    type="radio"
                    name="resolution"
                    value="yes"
                    checked={resolution === "yes"}
                    onChange={() => setResolution("yes")}
                    className="mr-2"
                  />
                  <span className="text-green-600 font-medium">YES</span>
                </label>
                <label className="flex items-center">
                  <input
                    type="radio"
                    name="resolution"
                    value="no"
                    checked={resolution === "no"}
                    onChange={() => setResolution("no")}
                    className="mr-2"
                  />
                  <span className="text-red-600 font-medium">NO</span>
                </label>
                <label className="flex items-center">
                  <input
                    type="radio"
                    name="resolution"
                    value="invalid"
                    checked={resolution === "invalid"}
                    onChange={() => setResolution("invalid")}
                    className="mr-2"
                  />
                  <span className="text-yellow-600 font-medium">INVALID</span>
                </label>
              </div>
            </div>

            <div>
              <label htmlFor="resolveNotes" className="label">
                Notes (optional)
              </label>
              <textarea
                id="resolveNotes"
                value={resolveNotes}
                onChange={(e) => setResolveNotes(e.target.value)}
                className="input min-h-[80px]"
                placeholder="Explain your resolution..."
              />
            </div>

            <button
              onClick={handleResolve}
              disabled={isResolving}
              className="btn-primary"
            >
              {isResolving ? "Resolving..." : "Resolve Prediction"}
            </button>
          </div>
        </div>
      )}

      {/* Trades list */}
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">All Bets</h2>

        {prediction.trades.length === 0 ? (
          <p className="text-gray-500">No bets placed yet.</p>
        ) : (
          <div className="space-y-3">
            {prediction.trades
              .filter((t) => t.state === "active")
              .map((trade) => (
                <div
                  key={trade._id}
                  className={`p-3 rounded ${
                    trade.bettorIsSkeptic ? "bg-red-50" : "bg-green-50"
                  }`}
                >
                  <div className="flex justify-between items-center">
                    <div>
                      <Link
                        href={`/user/${trade.bettorUsername}`}
                        className="font-medium link"
                      >
                        {trade.bettorUsername}
                      </Link>
                      <span
                        className={
                          trade.bettorIsSkeptic
                            ? "text-red-600 ml-2"
                            : "text-green-600 ml-2"
                        }
                      >
                        bets {trade.bettorIsSkeptic ? "NO" : "YES"}
                      </span>
                    </div>
                    <div className="text-right">
                      <p className="font-semibold">
                        {formatCents(trade.bettorStakeCents)}
                      </p>
                      <p className="text-xs text-gray-500">
                        vs {formatCents(trade.creatorStakeCents)}
                      </p>
                    </div>
                  </div>
                  {trade.notes && (
                    <p className="text-sm text-gray-600 mt-1">{trade.notes}</p>
                  )}
                  <p className="text-xs text-gray-400 mt-1">
                    {formatDateTime(trade.transactedAt)}
                  </p>
                </div>
              ))}
          </div>
        )}
      </div>

      {/* Resolution history */}
      {prediction.resolution && prediction.resolution.resolution !== "none_yet" && (
        <div className="card">
          <h2 className="text-lg font-semibold mb-4">Resolution</h2>
          <div
            className={`p-4 rounded ${
              prediction.resolution.resolution === "yes"
                ? "bg-green-50"
                : prediction.resolution.resolution === "no"
                ? "bg-red-50"
                : "bg-yellow-50"
            }`}
          >
            <p
              className={`font-bold text-lg ${getResolutionColorClass(
                prediction.resolution.resolution
              )}`}
            >
              {getResolutionText(prediction.resolution.resolution)}
            </p>
            {prediction.resolution.notes && (
              <p className="text-gray-700 mt-2">{prediction.resolution.notes}</p>
            )}
            <p className="text-sm text-gray-500 mt-2">
              Resolved {formatDateTime(prediction.resolution.resolvedAt)}
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
