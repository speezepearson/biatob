"use client";

import {
  createContext,
  useContext,
  useState,
  useEffect,
  ReactNode,
} from "react";
import { useQuery, useMutation } from "convex/react";
import { api } from "@/convex/_generated/api";
import { Id } from "@/convex/_generated/dataModel";

interface User {
  _id: Id<"users">;
  username: string;
  email: string;
  createdAt: number;
}

interface AuthContextType {
  user: User | null;
  token: string | null;
  isLoading: boolean;
  login: (username: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  register: (username: string, email: string, password: string) => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

const TOKEN_KEY = "biatob_auth_token";

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setToken] = useState<string | null>(null);
  const [isInitialized, setIsInitialized] = useState(false);

  // Load token from localStorage on mount
  useEffect(() => {
    const storedToken = localStorage.getItem(TOKEN_KEY);
    if (storedToken) {
      setToken(storedToken);
    }
    setIsInitialized(true);
  }, []);

  // Get current user from token
  const user = useQuery(
    api.auth.getCurrentUser,
    isInitialized ? { token: token ?? undefined } : "skip"
  );

  const loginMutation = useMutation(api.auth.login);
  const logoutMutation = useMutation(api.auth.logout);
  const registerMutation = useMutation(api.auth.register);

  const login = async (username: string, password: string) => {
    const result = await loginMutation({ username, password });
    localStorage.setItem(TOKEN_KEY, result.token);
    setToken(result.token);
  };

  const logout = async () => {
    if (token) {
      try {
        await logoutMutation({ token });
      } catch (e) {
        // Ignore errors on logout
      }
    }
    localStorage.removeItem(TOKEN_KEY);
    setToken(null);
  };

  const register = async (username: string, email: string, password: string) => {
    const result = await registerMutation({ username, email, password });
    localStorage.setItem(TOKEN_KEY, result.token);
    setToken(result.token);
  };

  const isLoading = !isInitialized || (token !== null && user === undefined);

  return (
    <AuthContext.Provider
      value={{
        user: user ?? null,
        token,
        isLoading,
        login,
        logout,
        register,
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
