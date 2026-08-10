import {
  Button,
  Heading,
  Hr,
  Section,
  Text,
} from "@react-email/components";
import * as React from "react";
import { EmailLayout } from "./components/EmailLayout";

interface ResolutionNotificationEmailProps {
  recipientUsername: string;
  predictionText: string;
  predictionUrl: string;
  resolution: "yes" | "no" | "invalid";
  creatorUsername: string;
}

export function ResolutionNotificationEmail({
  recipientUsername = "bob",
  predictionText = "Bitcoin will hit $100k by end of 2024",
  predictionUrl = "https://biatob.com/p/abc123",
  resolution = "yes",
  creatorUsername = "alice",
}: ResolutionNotificationEmailProps) {
  const resolutionConfig = {
    yes: {
      color: "#16a34a",
      bgColor: "#f0fdf4",
      borderColor: "#16a34a",
      label: "YES",
      description: "The prediction came true!",
    },
    no: {
      color: "#dc2626",
      bgColor: "#fef2f2",
      borderColor: "#dc2626",
      label: "NO",
      description: "The prediction did not come true.",
    },
    invalid: {
      color: "#ca8a04",
      bgColor: "#fefce8",
      borderColor: "#ca8a04",
      label: "INVALID",
      description: "The prediction was marked as invalid.",
    },
  };

  const config = resolutionConfig[resolution];

  return (
    <EmailLayout preview={`Prediction resolved: ${predictionText.slice(0, 40)}...`}>
      <Heading style={heading}>Prediction Resolved</Heading>
      <Text style={paragraph}>Hi {recipientUsername},</Text>
      <Text style={paragraph}>
        A prediction you&apos;re following has been resolved by{" "}
        <strong style={{ color: "#2563eb" }}>{creatorUsername}</strong>:
      </Text>
      <Section
        style={{
          ...predictionBox,
          backgroundColor: config.bgColor,
          borderLeftColor: config.borderColor,
        }}
      >
        <Text style={predictionText_style}>{predictionText}</Text>
        <Section style={resolutionBadgeContainer}>
          <Text
            style={{
              ...resolutionBadge,
              backgroundColor: config.color,
            }}
          >
            {config.label}
          </Text>
        </Section>
        <Text style={{ ...resolutionDesc, color: config.color }}>
          {config.description}
        </Text>
      </Section>
      <Text style={paragraph}>
        Visit the prediction page to see the final results and any notes from
        the creator.
      </Text>
      <Section style={buttonContainer}>
        <Button style={button} href={predictionUrl}>
          View Prediction
        </Button>
      </Section>
      <Hr style={hr} />
      <Text style={secondaryText}>
        You received this email because you placed a bet on or are following
        this prediction. You can manage your notification preferences in your
        account settings.
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

const predictionBox = {
  borderRadius: "8px",
  borderLeft: "4px solid",
  margin: "24px 0",
  padding: "20px",
};

const predictionText_style = {
  color: "#1f2937",
  fontSize: "16px",
  fontWeight: "600" as const,
  lineHeight: "24px",
  margin: "0 0 16px",
};

const resolutionBadgeContainer = {
  margin: "0 0 8px",
};

const resolutionBadge = {
  color: "#ffffff",
  fontSize: "14px",
  fontWeight: "bold" as const,
  padding: "6px 16px",
  borderRadius: "4px",
  display: "inline-block",
  margin: "0",
};

const resolutionDesc = {
  fontSize: "14px",
  margin: "8px 0 0",
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

const secondaryText = {
  color: "#6b7280",
  fontSize: "14px",
  lineHeight: "20px",
  margin: "0",
};

export default ResolutionNotificationEmail;
