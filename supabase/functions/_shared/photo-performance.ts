const stages = ["download", "vision", "normalization", "catalog"] as const;
type Stage = typeof stages[number];
type Outcome = "complete" | "failed";

/** Per-attempt server processing only: no user data, prompts or image paths. */
export class PhotoPerformance {
  private readonly started: number;
  private stopped: number | undefined;
  private readonly durations: Partial<
    Record<Stage, { elapsedMs: number; outcome: Outcome }>
  > = {};
  constructor(private readonly clock: () => number = () => performance.now()) {
    this.started = clock();
  }
  async measure<T>(stage: Stage, operation: () => Promise<T>): Promise<T> {
    const started = this.clock();
    let outcome: Outcome = "failed";
    try {
      const result = await operation();
      outcome = "complete";
      return result;
    } finally {
      this.durations[stage] = { elapsedMs: this.elapsed(started), outcome };
    }
  }
  private elapsed(started: number) {
    return Math.max(0, Math.round(this.clock() - started));
  }
  snapshot(outcome: Outcome) {
    this.stopped ??= this.clock();
    return {
      version: 1,
      scope: "server_photo_processing",
      outcome,
      totalMs: Math.max(0, Math.round(this.stopped - this.started)),
      stages: Object.fromEntries(
        stages.filter((stage) => this.durations[stage]).map((
          stage,
        ) => [stage, { ...this.durations[stage]! }]),
      ),
    };
  }
}
