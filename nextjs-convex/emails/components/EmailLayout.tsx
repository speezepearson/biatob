import {
  Body,
  Container,
  Head,
  Html,
  Img,
  Link,
  Preview,
  Section,
  Text,
} from "@react-email/components";
import * as React from "react";

interface EmailLayoutProps {
  preview: string;
  children: React.ReactNode;
}

export function EmailLayout({ preview, children }: EmailLayoutProps) {
  return (
    <Html>
      <Head />
      <Preview>{preview}</Preview>
      <Body style={main}>
        <Container style={container}>
          <Section style={header}>
            <Text style={logo}>BIATOB</Text>
            <Text style={tagline}>Honor-Based Prediction Markets</Text>
          </Section>
          <Section style={content}>{children}</Section>
          <Section style={footer}>
            <Text style={footerText}>
              BIATOB - Bet I Am The Only Bettor
            </Text>
            <Text style={footerText}>
              <Link href="https://biatob.com" style={footerLink}>
                biatob.com
              </Link>
            </Text>
          </Section>
        </Container>
      </Body>
    </Html>
  );
}

const main = {
  backgroundColor: "#f6f9fc",
  fontFamily:
    '-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Ubuntu,sans-serif',
};

const container = {
  backgroundColor: "#ffffff",
  margin: "0 auto",
  padding: "20px 0 48px",
  marginBottom: "64px",
  maxWidth: "600px",
};

const header = {
  padding: "32px 48px 24px",
  borderBottom: "1px solid #e6ebf1",
};

const logo = {
  color: "#2563eb",
  fontSize: "28px",
  fontWeight: "bold" as const,
  margin: "0",
  padding: "0",
};

const tagline = {
  color: "#6b7280",
  fontSize: "14px",
  margin: "4px 0 0",
  padding: "0",
};

const content = {
  padding: "32px 48px",
};

const footer = {
  padding: "24px 48px",
  borderTop: "1px solid #e6ebf1",
  textAlign: "center" as const,
};

const footerText = {
  color: "#8898aa",
  fontSize: "12px",
  lineHeight: "16px",
  margin: "0",
};

const footerLink = {
  color: "#2563eb",
  textDecoration: "none",
};

export default EmailLayout;
