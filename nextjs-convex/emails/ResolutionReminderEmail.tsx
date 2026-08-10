import {
  Button,
  Heading,
  Hr,
  Section,
  Text,
} from "@react-email/components";
import * as React from "react";
import { EmailLayout } from "./components/EmailLayout";

interface ResolutionReminderEmailProps {
  creatorUsername: string;
  predictionText: string;
  predictionUrl: string;
  resolvesAt: string;
  totalStaked: string;
}

export function ResolutionReminderEmail({
  creatorUsername = "alice",
  predictionText = "Bitcoin will hit $100k by end of 2024",
  predictionUrl = "https://biatob.com/p/abc123",
  resolvesAt = "January 1, 2025",
  totalStaked = "$250",
}: ResolutionReminderEmailProps) {
  return (
    <EmailLayout preview={`Time to resolve: ${predictionText.slice(0, 40)}...`}>
      <Heading style={heading}>Time to Resolve Your Prediction</Heading>
      <Text style={paragraph}>Hi {creatorUsername},</Text>
      <Text style={paragraph}>
        Your prediction is ready to be resolved. The resolution date ({resolvesAt})
        has passed, and people are waiting to know the outcome!
      </Text>
      <Section style={predictionBox}>
        <Text style={predictionLabel}>YOUR PREDICTION</Text>
        <Text style={predictionText_style}>{predictionText}</Text>
        <Section style={statsRow}>
          <Text style={statItem}>
            <span style={statLabel}>Resolution Date:</span>
            <br />
            <span style={statValue}>{resolvesAt}</span>
          </Text>
          <Text style={statItem}>
            <span style={statLabel}>Total Staked:</span>
            <br />
            <span style={statValue}>{totalStaked}</span>
          </Text>
        </Section>
      </Section>
      <Text style={paragraph}>
        Please resolve your prediction as <strong>Yes</strong>, <strong>No</strong>,
        or <strong>Invalid</strong> based on what actually happened.
      </Text>
      <Section style={buttonContainer}>
        <Button style={button} href={predictionUrl}>
          Resolve Prediction
        </Button>
      </Section>
      <Hr style={hr} />
      <Section style={reminderBox}>
        <Text style={reminderTitle}>Why Timely Resolution Matters</Text>
        <Text style={reminderText}>
          BIATOB is built on trust and intellectual honesty. Resolving predictions
          promptly shows respect for the people who bet with you and maintains the
          integrity of the platform. Unresolved predictions can damage your
          reputation as a reliable predictor.
        </Text>
      </Section>
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

const predictionBox = {
  background: "#f9fafb",
  borderRadius: "8px",
  border: "1px solid #e5e7eb",
  margin: "24px 0",
  padding: "24px",
};

const predictionLabel = {
  color: "#6b7280",
  fontSize: "12px",
  fontWeight: "bold" as const,
  letterSpacing: "0.5px",
  margin: "0 0 8px",
};

const predictionText_style = {
  color: "#1f2937",
  fontSize: "18px",
  fontWeight: "600" as const,
  lineHeight: "26px",
  margin: "0 0 20px",
};

const statsRow = {
  borderTop: "1px solid #e5e7eb",
  paddingTop: "16px",
};

const statItem = {
  color: "#374151",
  fontSize: "14px",
  margin: "0 0 12px",
};

const statLabel = {
  color: "#6b7280",
  fontSize: "12px",
  textTransform: "uppercase" as const,
  letterSpacing: "0.5px",
};

const statValue = {
  color: "#1f2937",
  fontSize: "16px",
  fontWeight: "600" as const,
};

const buttonContainer = {
  textAlign: "center" as const,
  margin: "32px 0",
};

const button = {
  backgroundColor: "#2563eb",
  borderRadius: "6px",
  color: "#fff",
  fontSize: "16px",
  fontWeight: "bold" as const,
  textDecoration: "none",
  textAlign: "center" as const,
  display: "inline-block",
  padding: "14px 32px",
};

const hr = {
  borderColor: "#e6ebf1",
  margin: "24px 0",
};

const reminderBox = {
  background: "#fffbeb",
  borderRadius: "8px",
  borderLeft: "4px solid #f59e0b",
  padding: "16px 20px",
};

const reminderTitle = {
  color: "#b45309",
  fontSize: "14px",
  fontWeight: "bold" as const,
  margin: "0 0 8px",
};

const reminderText = {
  color: "#92400e",
  fontSize: "14px",
  lineHeight: "20px",
  margin: "0",
};

export default ResolutionReminderEmail;
