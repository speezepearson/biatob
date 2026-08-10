import {
  Button,
  Heading,
  Hr,
  Section,
  Text,
} from "@react-email/components";
import * as React from "react";
import { EmailLayout } from "./components/EmailLayout";

interface InvitationEmailProps {
  inviterUsername: string;
  inviteUrl: string;
}

export function InvitationEmail({
  inviterUsername = "alice",
  inviteUrl = "https://biatob.com/invite/abc123",
}: InvitationEmailProps) {
  return (
    <EmailLayout preview={`${inviterUsername} invited you to BIATOB`}>
      <Heading style={heading}>You&apos;ve Been Invited!</Heading>
      <Text style={paragraph}>
        <strong style={highlight}>{inviterUsername}</strong> has invited you to
        join BIATOB, an honor-based prediction market platform.
      </Text>
      <Section style={infoBox}>
        <Text style={infoTitle}>What is BIATOB?</Text>
        <Text style={infoText}>
          BIATOB (Bet I Am The Only Bettor) is a platform where you can make
          predictions about the future and bet with trusted friends. It&apos;s
          honor-based &mdash; no real money changes hands, but your reputation is on
          the line!
        </Text>
      </Section>
      <Text style={paragraph}>
        By accepting this invitation, you&apos;ll establish{" "}
        <strong>mutual trust</strong> with {inviterUsername}, allowing you to
        bet on each other&apos;s predictions.
      </Text>
      <Section style={buttonContainer}>
        <Button style={button} href={inviteUrl}>
          Accept Invitation
        </Button>
      </Section>
      <Hr style={hr} />
      <Text style={secondaryText}>
        Or copy and paste this URL into your browser:
      </Text>
      <Text style={urlText}>{inviteUrl}</Text>
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

const highlight = {
  color: "#2563eb",
};

const infoBox = {
  background: "#eff6ff",
  borderRadius: "8px",
  borderLeft: "4px solid #2563eb",
  margin: "24px 0",
  padding: "16px 20px",
};

const infoTitle = {
  color: "#1e40af",
  fontSize: "14px",
  fontWeight: "bold" as const,
  margin: "0 0 8px",
  textTransform: "uppercase" as const,
  letterSpacing: "0.5px",
};

const infoText = {
  color: "#374151",
  fontSize: "14px",
  lineHeight: "20px",
  margin: "0",
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
  margin: "0 0 8px",
};

const urlText = {
  color: "#2563eb",
  fontSize: "12px",
  lineHeight: "20px",
  margin: "0",
  wordBreak: "break-all" as const,
};

export default InvitationEmail;
