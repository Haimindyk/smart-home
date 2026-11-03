import React from "react";
import { createRoot } from "react-dom/client";
import { AiTrainer } from "../../../src/components/health/ai-trainer";
import { Nutrition } from "../../../src/components/health/nutrition";
function App() {
  return (
    <main className="health-app mx-auto w-full max-w-3xl p-4">
      <AiTrainer date="2026-11-03" />
      <Nutrition date="2026-11-03" />
    </main>
  );
}
createRoot(document.getElementById("root")!).render(<App />);
