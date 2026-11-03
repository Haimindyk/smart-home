type NutrientRingProps = {
  value: number;
  target?: number | null;
  label: string;
  color?: string;
  trackColor?: string;
};

export function NutrientRing({
  value,
  target,
  label,
  color = "currentColor",
  trackColor = "#e9edf0",
}: NutrientRingProps) {
  const progress = Number.isFinite(value) && typeof target === "number" && Number.isFinite(target) && target > 0
    ? Math.min(100, Math.max(0, (value / target) * 100))
    : 0;

  return (
    <svg
      className="health-progress-ring"
      viewBox="0 0 140 140"
      role="progressbar"
      aria-label={label}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={progress}
    >
      <circle cx="70" cy="70" r="59" fill="none" stroke={trackColor} strokeWidth="10" />
      {progress > 0 && (
        <circle
          cx="70"
          cy="70"
          r="59"
          fill="none"
          stroke={color}
          strokeWidth="10"
          strokeLinecap="round"
          pathLength="100"
          strokeDasharray={`${progress} 100`}
        />
      )}
    </svg>
  );
}
