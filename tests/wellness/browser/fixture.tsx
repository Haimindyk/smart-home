import React from "react";
import { createRoot } from "react-dom/client";
import { AiTrainer } from "../../../src/components/health/ai-trainer";
import { Nutrition } from "../../../src/components/health/nutrition";
import { TrainingData } from "../../../src/components/health/training-data";
import { HealthPage } from "../../../src/components/health/health-page";
import { CoachChat } from "../../../src/components/health/coach-chat";
function App() {
  if(new URLSearchParams(location.search).has("preview"))return <HealthPage/>;
  return (
    <main className="health-app mx-auto w-full max-w-3xl p-4">
      <AiTrainer date="2026-11-03" />
      <Nutrition date="2026-11-03" />
      <TrainingData />
      <CoachChat />
    </main>
  );
}
createRoot(document.getElementById("root")!).render(<App />);
