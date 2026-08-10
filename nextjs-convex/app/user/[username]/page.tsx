"use client";

import { useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { useQuery, useMutation } from "convex/react";
import { api } from "@/convex/_generated/api";
import { useAuth } from "@/lib/auth";
import { formatDate, formatProbability, getResolutionText, getResolutionColorClass } from "@/lib/utils";

export default function UserProfilePage() {
  const params = useParams();
  const username = params.username as string;
  const { user: currentUser, token } = useAuth();

  const profile = useQuery(api.relationships.getUser, {
    username,
    token: token ?? undefined,
  });

  const setTrusted = useMutation(api.relationships.setTrusted);
  const [isUpdating, setIsUpdating] = useState(false);

  if (profile === undefined) {
    return <div className="text-center text-gray-500">Loading...</div>;
  }

  if (profile === null) {
    return (
      <div className="card text-center">
        <h1 className="text-2xl font-bold text-gray-900 mb-2">User Not Found</h1>
        <p className="text-gray-600">This user doesn&apos;t exist.</p>
      </div>
    );
  }

  const isOwnProfile = currentUser && currentUser.username === username;

  const handleToggleTrust = async () => {
    if (!token) return;
    setIsUpdating(true);
    try {
      await setTrusted({
        token,
        targetUsername: username,
        trusted: !profile.isTrustedByMe,
      });
    } finally {
      setIsUpdating(false);
    }
  };

  return (
    <div className="space-y-6">
      <div className="card">
        <div className="flex justify-between items-start">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">{profile.username}</h1>
            <p className="text-gray-500">Member since {formatDate(profile.createdAt)}</p>
          </div>

          {currentUser && !isOwnProfile && (
            <div className="text-right">
              <button
                onClick={handleToggleTrust}
                disabled={isUpdating}
                className={profile.isTrustedByMe ? "btn-secondary" : "btn-primary"}
              >
                {profile.isTrustedByMe ? "Remove Trust" : "Trust User"}
              </button>
            </div>
          )}
        </div>

        {!isOwnProfile && currentUser && (
          <div className="mt-4 p-4 bg-gray-50 rounded">
            <h3 className="text-sm font-medium text-gray-700 mb-2">Trust Status</h3>
            <div className="flex items-center space-x-4">
              <div className="flex items-center">
                <div
                  className={`w-3 h-3 rounded-full mr-2 ${
                    profile.isTrustedByMe ? "bg-green-500" : "bg-gray-300"
                  }`}
                />
                <span className="text-sm text-gray-600">
                  {profile.isTrustedByMe ? "You trust them" : "You don't trust them"}
                </span>
              </div>
              <div className="flex items-center">
                <div
                  className={`w-3 h-3 rounded-full mr-2 ${
                    profile.trustsMe ? "bg-green-500" : "bg-gray-300"
                  }`}
                />
                <span className="text-sm text-gray-600">
                  {profile.trustsMe ? "They trust you" : "They don't trust you"}
                </span>
              </div>
            </div>
            {profile.mutualTrust && (
              <p className="mt-2 text-sm text-green-600 font-medium">
                Mutual trust established
              </p>
            )}
          </div>
        )}

        {isOwnProfile && (
          <div className="mt-4">
            <Link href="/settings" className="link">
              Edit Settings
            </Link>
          </div>
        )}
      </div>

      <div>
        <h2 className="text-xl font-semibold mb-4">Recent Predictions</h2>

        {profile.recentPredictions.length === 0 ? (
          <div className="card">
            <p className="text-gray-500">No predictions yet.</p>
          </div>
        ) : (
          <div className="space-y-3">
            {profile.recentPredictions.map((prediction: any) => (
              <Link
                key={prediction._id}
                href={`/p/${prediction.predictionId}`}
                className="card block hover:shadow-md transition-shadow"
              >
                <p className="font-medium text-gray-900 mb-1">
                  {prediction.prediction}
                </p>
                <p className="text-sm text-gray-500">
                  {formatProbability(prediction.certaintyLowP)}-
                  {formatProbability(prediction.certaintyHighP)} confident
                  &middot; {formatDate(prediction.createdAt)}
                </p>
              </Link>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
