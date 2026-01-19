"use client";

import Link from "next/link";
import { useAuth } from "@/lib/auth";

export function Navbar() {
  const { user, isLoading, logout } = useAuth();

  return (
    <nav className="bg-white shadow-sm border-b">
      <div className="container mx-auto px-4 max-w-4xl">
        <div className="flex justify-between items-center h-16">
          <div className="flex items-center space-x-8">
            <Link href="/" className="text-xl font-bold text-blue-600">
              BIATOB
            </Link>
            {user && (
              <div className="hidden md:flex space-x-4">
                <Link href="/predictions/new" className="text-gray-600 hover:text-gray-900">
                  New Prediction
                </Link>
                <Link href="/my-stakes" className="text-gray-600 hover:text-gray-900">
                  My Stakes
                </Link>
              </div>
            )}
          </div>

          <div className="flex items-center space-x-4">
            {isLoading ? (
              <span className="text-gray-400">Loading...</span>
            ) : user ? (
              <>
                <Link
                  href={`/user/${user.username}`}
                  className="text-gray-600 hover:text-gray-900"
                >
                  {user.username}
                </Link>
                <Link href="/settings" className="text-gray-600 hover:text-gray-900">
                  Settings
                </Link>
                <button
                  onClick={logout}
                  className="text-gray-600 hover:text-gray-900"
                >
                  Sign out
                </button>
              </>
            ) : (
              <>
                <Link href="/login" className="text-gray-600 hover:text-gray-900">
                  Log in
                </Link>
                <Link href="/signup" className="btn-primary">
                  Sign up
                </Link>
              </>
            )}
          </div>
        </div>
      </div>
    </nav>
  );
}
