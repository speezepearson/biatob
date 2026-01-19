"use client";

import {
  createContext,
  useContext,
  useState,
  ReactNode,
} from "react";
import { useQuery, useMutation } from "convex/react";
import {
  useConvexAuth,
  Authenticated,
  Unauthenticated,
  AuthLoading,
} from "convex/react";
import { api } from "@/convex/_generated/api";
import { Id } from "@/convex/_generated/dataModel";

interface User {
  _id: Id<"users">;
  username?: string;
  email?: string;
  name?: string;
  createdAt?: number;
}

interface AuthContextType {
  user: User | null;
  isLoading: boolean;
  isAuthenticated: boolean;
  needsUsername: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const { isLoading, isAuthenticated } = useConvexAuth();

  // Get current user when authenticated
  const user = useQuery(
    api.auth.currentUser,
    isAuthenticated ? {} : "skip"
  );

  const needsUsername = isAuthenticated && user !== undefined && !user?.username;

  return (
    <AuthContext.Provider
      value={{
        user: user ?? null,
        isLoading: isLoading || (isAuthenticated && user === undefined),
        isAuthenticated,
        needsUsername,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return context;
}

// Re-export Convex Auth components for convenience
export { Authenticated, Unauthenticated, AuthLoading };
