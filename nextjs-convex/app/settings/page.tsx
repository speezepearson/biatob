"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery, useMutation } from "convex/react";
import { api } from "@/convex/_generated/api";
import { useAuth } from "@/lib/auth";

export default function SettingsPage() {
  const { user, token, isLoading: authLoading } = useAuth();

  const settings = useQuery(
    api.relationships.getSettings,
    token ? { token } : "skip"
  );

  const changePassword = useMutation(api.auth.changePassword);
  const setTrusted = useMutation(api.relationships.setTrusted);
  const sendInvitation = useMutation(api.relationships.sendInvitation);

  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [passwordError, setPasswordError] = useState<string | null>(null);
  const [passwordSuccess, setPasswordSuccess] = useState(false);
  const [isChangingPassword, setIsChangingPassword] = useState(false);

  const [inviteEmail, setInviteEmail] = useState("");
  const [inviteError, setInviteError] = useState<string | null>(null);
  const [inviteSuccess, setInviteSuccess] = useState<string | null>(null);
  const [isInviting, setIsInviting] = useState(false);

  if (authLoading) {
    return <div className="text-center text-gray-500">Loading...</div>;
  }

  if (!user || !token) {
    return (
      <div className="card text-center">
        <p className="text-gray-600">Please log in to view settings.</p>
        <Link href="/login" className="link">
          Log in
        </Link>
      </div>
    );
  }

  if (settings === undefined) {
    return <div className="text-center text-gray-500">Loading settings...</div>;
  }

  const handleChangePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setPasswordError(null);
    setPasswordSuccess(false);

    if (newPassword !== confirmPassword) {
      setPasswordError("Passwords do not match");
      return;
    }

    if (newPassword.length < 8) {
      setPasswordError("Password must be at least 8 characters");
      return;
    }

    setIsChangingPassword(true);

    try {
      await changePassword({
        token,
        currentPassword,
        newPassword,
      });
      setPasswordSuccess(true);
      setCurrentPassword("");
      setNewPassword("");
      setConfirmPassword("");
    } catch (err: any) {
      setPasswordError(err.message || "Failed to change password");
    } finally {
      setIsChangingPassword(false);
    }
  };

  const handleRemoveTrust = async (username: string) => {
    await setTrusted({
      token,
      targetUsername: username,
      trusted: false,
    });
  };

  const handleSendInvitation = async (e: React.FormEvent) => {
    e.preventDefault();
    setInviteError(null);
    setInviteSuccess(null);
    setIsInviting(true);

    try {
      const result = await sendInvitation({
        token,
        recipientEmail: inviteEmail,
      });

      if (result.alreadyUser) {
        setInviteSuccess(
          `${inviteEmail} is already a user. Trust relationship created.`
        );
      } else {
        setInviteSuccess(`Invitation sent to ${inviteEmail}`);
      }
      setInviteEmail("");
    } catch (err: any) {
      setInviteError(err.message || "Failed to send invitation");
    } finally {
      setIsInviting(false);
    }
  };

  return (
    <div className="space-y-8 max-w-2xl">
      <h1 className="text-2xl font-bold">Settings</h1>

      {/* Account Info */}
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Account</h2>
        <div className="space-y-2">
          <div>
            <span className="text-gray-500">Username:</span>{" "}
            <span className="font-medium">{settings.user.username}</span>
          </div>
          <div>
            <span className="text-gray-500">Email:</span>{" "}
            <span className="font-medium">{settings.user.email}</span>
          </div>
        </div>
      </div>

      {/* Change Password */}
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Change Password</h2>

        {passwordError && (
          <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded mb-4">
            {passwordError}
          </div>
        )}

        {passwordSuccess && (
          <div className="bg-green-50 border border-green-200 text-green-700 px-4 py-3 rounded mb-4">
            Password changed successfully
          </div>
        )}

        <form onSubmit={handleChangePassword} className="space-y-4">
          <div>
            <label htmlFor="currentPassword" className="label">
              Current Password
            </label>
            <input
              type="password"
              id="currentPassword"
              value={currentPassword}
              onChange={(e) => setCurrentPassword(e.target.value)}
              className="input"
              required
            />
          </div>
          <div>
            <label htmlFor="newPassword" className="label">
              New Password
            </label>
            <input
              type="password"
              id="newPassword"
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              className="input"
              required
              minLength={8}
            />
          </div>
          <div>
            <label htmlFor="confirmPassword" className="label">
              Confirm New Password
            </label>
            <input
              type="password"
              id="confirmPassword"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              className="input"
              required
            />
          </div>
          <button
            type="submit"
            disabled={isChangingPassword}
            className="btn-primary"
          >
            {isChangingPassword ? "Changing..." : "Change Password"}
          </button>
        </form>
      </div>

      {/* Trusted Users */}
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Trusted Users</h2>

        {settings.trustedUsers.length === 0 ? (
          <p className="text-gray-500">You haven&apos;t trusted anyone yet.</p>
        ) : (
          <div className="space-y-2">
            {settings.trustedUsers.map((user: any) => (
              <div
                key={user._id}
                className="flex justify-between items-center p-2 bg-gray-50 rounded"
              >
                <div>
                  <Link href={`/user/${user.username}`} className="link font-medium">
                    {user.username}
                  </Link>
                  {user.trustsMe && (
                    <span className="ml-2 text-xs text-green-600">
                      (trusts you back)
                    </span>
                  )}
                </div>
                <button
                  onClick={() => handleRemoveTrust(user.username)}
                  className="text-sm text-red-600 hover:text-red-800"
                >
                  Remove
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Users Who Trust Me */}
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Users Who Trust Me</h2>

        {settings.trustedByUsers.length === 0 ? (
          <p className="text-gray-500">Nobody trusts you yet.</p>
        ) : (
          <div className="space-y-2">
            {settings.trustedByUsers.map((user: any) => (
              <div
                key={user._id}
                className="flex justify-between items-center p-2 bg-gray-50 rounded"
              >
                <div>
                  <Link href={`/user/${user.username}`} className="link font-medium">
                    {user.username}
                  </Link>
                  {user.isTrustedByMe && (
                    <span className="ml-2 text-xs text-green-600">
                      (you trust them)
                    </span>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Send Invitation */}
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Invite Someone</h2>
        <p className="text-gray-600 mb-4">
          Invite someone to BIATOB and establish mutual trust.
        </p>

        {inviteError && (
          <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded mb-4">
            {inviteError}
          </div>
        )}

        {inviteSuccess && (
          <div className="bg-green-50 border border-green-200 text-green-700 px-4 py-3 rounded mb-4">
            {inviteSuccess}
          </div>
        )}

        <form onSubmit={handleSendInvitation} className="flex space-x-2">
          <input
            type="email"
            value={inviteEmail}
            onChange={(e) => setInviteEmail(e.target.value)}
            className="input flex-1"
            placeholder="email@example.com"
            required
          />
          <button
            type="submit"
            disabled={isInviting}
            className="btn-primary"
          >
            {isInviting ? "Sending..." : "Send Invite"}
          </button>
        </form>

        {settings.sentInvitations.length > 0 && (
          <div className="mt-4">
            <h3 className="text-sm font-medium text-gray-700 mb-2">
              Pending Invitations
            </h3>
            <div className="space-y-1">
              {settings.sentInvitations
                .filter((i: any) => !i.accepted)
                .map((inv: any, idx: number) => (
                  <div key={idx} className="text-sm text-gray-600">
                    {inv.recipientEmail}
                  </div>
                ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
