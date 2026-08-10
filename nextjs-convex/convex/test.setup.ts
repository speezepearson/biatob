import { vi } from "vitest";

// Mock environment variables for tests
vi.stubEnv("RESEND_API_KEY", "re_test_key");
vi.stubEnv("EMAIL_FROM", "BIATOB <test@example.com>");
vi.stubEnv("BASE_URL", "http://localhost:3000");
