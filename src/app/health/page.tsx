import type { Metadata } from "next";
import { HealthPage } from "@/components/health/health-page";

export const metadata: Metadata = {
  title: "KH Wellness · הבריאות שלי",
  description: "המרחב האישי שלך לתזונה, אימונים והתקדמות.",
};

export default function Page() {
  return <HealthPage />;
}
