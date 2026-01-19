"use client";

import { useState, useEffect } from "react";
import { useParams, useRouter } from "next/navigation";
import Link from "next/link";
import { useQuery, useMutation } from "convex/react";
import { api } from "@/convex/_generated/api";
import { useAuth } from "@/lib/auth";

export default function AcceptInvitationPage() {
  const params = useParams();
  const router = useRouter();
  const nonce = params.nonce as string;
  const { user, token, isLoading: authLoading } = useAuth();

  const invitation = useQuery(api.relationships.checkInvitation, { nonce });
  const acceptInvitation = useMutation(api.relationships.acceptInvitation);

  const [error, setError] = useState<string | null>(null);
  const [isAccepting, setIsAccepting] = useState(false);
  const [accepted, setAccepted] = useState(false);

  if (authLoading) {
    return <div className="text-center text-gray-500">Loading...</div>;
  }

  if (invitation === undefined) {
    return <div className="text-center text-gray-500">Loading invitation...</div>;
  }

  if (invitation === null) {
    return (
      <div className="card text-center max-w-md mx-auto">
        <h1 className="text-2xl font-bold text-gray-900 mb-2">Invalid Invitation</h1>
        <p className="text-gray-600">This invitation link is invalid or has expired.</p>
      </div>
    );
  }

  if (invitation.alreadyAccepted) {
    return (
      <div className="card text-center max-w-md mx-auto">
        <h1 className="text-2xl font-bold text-gray-900 mb-2">Already Accepted</h1>
        <p className="text-gray-600">This invitation has already been accepted.</p>
        <Link href="/" className="link mt-4 block">
          Go to Home
        </Link>
      </div>
    );
  }

  const handleAccept = async () => {
    if (!token) return;
    setError(null);
    setIsAccepting(true);

    try {
      const result = await acceptInvitation({ nonce, token });
      setAccepted(true);
    } catch (err: any) {
      setError(err.message || "Failed to accept invitation");
    } finally {
      setIsAccepting(false);
    }
  };

  if (accepted) {
    return (
      <div className="card text-center max-w-md mx-auto">
        <h1 className="text-2xl font-bold text-green-600 mb-2">Invitation Accepted!</h1>
        <p className="text-gray-600 mb-4">
          You and {invitation.inviterUsername} now have mutual trust.
        </p>
        <Link href={`/user/${invitation.inviterUsername}`} className="btn-primary">
          View {invitation.inviterUsername}&apos;s Profile
        </Link>
      </div>
    );
  }

  return (
    <div className="card max-w-md mx-auto">
      <h1 className="text-2xl font-bold text-gray-900 mb-4">Accept Invitation</h1>

      <p className="text-gray-600 mb-6">
        <strong>{invitation.inviterUsername}</strong> has invited{" "}
        <strong>{invitation.recipientEmail}</strong> to join BIATOB and
        establish mutual trust.
      </p>

      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded mb-4">
          {error}
        </div>
      )}

      {!user ? (
        <div className="space-y-4">
          <p className="text-gray-600">
            You need to sign up or log in to accept this invitation.
          </p>
          <div className="flex space-x-4">
            <Link
              href={`/signup?redirect=/invite/${nonce}`}
              className="btn-primary flex-1 text-center"
            >
              Sign Up
            </Link>
            <Link
              href={`/login?redirect=/invite/${nonce}`}
              className="btn-secondary flex-1 text-center"
            >
              Log In
            </Link>
          </div>
        </div>
      ) : (
        <div className="space-y-4">
          <p className="text-gray-600">
            Logged in as <strong>{user.username}</strong>
          </p>
          <button
            onClick={handleAccept}
            disabled={isAccepting}
            className="btn-primary w-full"
          >
            {isAccepting ? "Accepting..." : "Accept Invitation"}
          </button>
        </div>
      )}
    </div>
  );
}
