import {
  Button,
  Heading,
  Hr,
  Section,
  Text,
} from "@react-email/components";
import * as React from "react";
import { EmailLayout } from "./components/EmailLayout";

interface VerificationEmailProps {
  code: string;
}

export function VerificationEmail({ code = "123456" }: VerificationEmailProps) {
  return (
    <EmailLayout preview="Your BIATOB verification code">
      <Heading style={heading}>Welcome to BIATOB</Heading>
      <Text style={paragraph}>
        Thanks for signing up! Use the verification code below to complete your
        registration:
      </Text>
      <Section style={codeContainer}>
        <Text style={codeText}>{code}</Text>
      </Section>
      <Text style={paragraph}>
        This code will expire in 24 hours. If you didn&apos;t create an account
        with BIATOB, you can safely ignore this email.
      </Text>
      <Hr style={hr} />
      <Text style={secondaryText}>
        BIATOB is an honor-based prediction market where you can make predictions
        and bet with trusted friends. No real money changes hands &mdash; it&apos;s all
        about reputation and intellectual honesty.
      </Text>
    </EmailLayout>
  );
}

const heading = {
  color: "#1f2937",
  fontSize: "24px",
  fontWeight: "bold" as const,
  margin: "0 0 16px",
  padding: "0",
};

const paragraph = {
  color: "#374151",
  fontSize: "16px",
  lineHeight: "24px",
  margin: "0 0 16px",
};

const codeContainer = {
  background: "#f3f4f6",
  borderRadius: "8px",
  margin: "24px 0",
  padding: "24px",
  textAlign: "center" as const,
};

const codeText = {
  color: "#1f2937",
  fontSize: "36px",
  fontWeight: "bold" as const,
  letterSpacing: "8px",
  margin: "0",
};

const hr = {
  borderColor: "#e6ebf1",
  margin: "24px 0",
};

const secondaryText = {
  color: "#6b7280",
  fontSize: "14px",
  lineHeight: "20px",
  margin: "0",
};

export default VerificationEmail;
