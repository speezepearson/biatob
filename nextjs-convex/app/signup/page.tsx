"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { useAuthActions } from "@convex-dev/auth/react";
import { useMutation } from "convex/react";
import { api } from "@/convex/_generated/api";
import { useAuth } from "@/lib/auth";

type Step = "signup" | "username";

export default function SignupPage() {
  const router = useRouter();
  const { signIn } = useAuthActions();
  const { isAuthenticated, needsUsername, isLoading: authLoading } = useAuth();
  const setUsername = useMutation(api.auth.setUsername);

  const [step, setStep] = useState<Step>("signup");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [username, setUsernameValue] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  // Redirect if already logged in with username
  if (isAuthenticated && !needsUsername && !authLoading) {
    router.push("/");
    return null;
  }

  // If authenticated but needs username, show username step
  if (isAuthenticated && needsUsername && step !== "username") {
    setStep("username");
  }

  const handleSignup = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (password !== confirmPassword) {
      setError("Passwords do not match");
      return;
    }

    if (password.length < 8) {
      setError("Password must be at least 8 characters");
      return;
    }

    setIsLoading(true);

    try {
      const formData = new FormData();
      formData.set("email", email);
      formData.set("password", password);
      formData.set("flow", "signUp");

      await signIn("password", formData);
      setStep("username");
    } catch (err: any) {
      setError(err.message || "Failed to create account");
    } finally {
      setIsLoading(false);
    }
  };

  const handleSetUsername = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setIsLoading(true);

    try {
      await setUsername({ username: username });
      router.push("/");
    } catch (err: any) {
      setError(err.message || "Failed to set username");
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="max-w-md mx-auto">
      <div className="card">
        <h1 className="text-2xl font-bold mb-6">
          {step === "signup" ? "Sign Up" : "Choose Username"}
        </h1>

        {error && (
          <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded mb-4">
            {error}
          </div>
        )}

        {step === "signup" && (
          <form onSubmit={handleSignup} className="space-y-4">
            <div>
              <label htmlFor="email" className="label">
                Email Address
              </label>
              <input
                type="email"
                id="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="input"
                required
                autoComplete="email"
              />
            </div>

            <div>
              <label htmlFor="password" className="label">
                Password
              </label>
              <input
                type="password"
                id="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="input"
                required
                autoComplete="new-password"
                minLength={8}
              />
              <p className="mt-1 text-sm text-gray-500">
                At least 8 characters.
              </p>
            </div>

            <div>
              <label htmlFor="confirmPassword" className="label">
                Confirm Password
              </label>
              <input
                type="password"
                id="confirmPassword"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                className="input"
                required
                autoComplete="new-password"
              />
            </div>

            <button
              type="submit"
              disabled={isLoading}
              className="btn-primary w-full"
            >
              {isLoading ? "Creating account..." : "Create Account"}
            </button>
          </form>
        )}

        {step === "username" && (
          <form onSubmit={handleSetUsername} className="space-y-4">
            <p className="text-sm text-gray-600 mb-4">
              Almost done! Choose a username for your account.
            </p>

            <div>
              <label htmlFor="username" className="label">
                Username
              </label>
              <input
                type="text"
                id="username"
                value={username}
                onChange={(e) => setUsernameValue(e.target.value)}
                className="input"
                required
                autoComplete="username"
                pattern="[a-zA-Z0-9_]{3,32}"
                title="3-32 characters, letters, numbers, and underscores only"
              />
              <p className="mt-1 text-sm text-gray-500">
                3-32 characters, letters, numbers, and underscores only.
              </p>
            </div>

            <button
              type="submit"
              disabled={isLoading}
              className="btn-primary w-full"
            >
              {isLoading ? "Setting username..." : "Complete Signup"}
            </button>
          </form>
        )}

        {step === "signup" && (
          <p className="mt-4 text-center text-sm text-gray-600">
            Already have an account?{" "}
            <Link href="/login" className="link">
              Log in
            </Link>
          </p>
        )}
      </div>
    </div>
  );
}
