/**
 * Wraps user-entered text (which may mix Hebrew, English, numbers, URLs) so
 * its base direction is computed from its own content rather than inheriting
 * the page direction — a Hebrew title with a trailing English brand name or
 * price won't scramble.
 */
export function BidiText({ text, className }: { text: string; className?: string }) {
  return (
    <span dir="auto" className={className} style={{ unicodeBidi: "isolate" }}>
      {text}
    </span>
  );
}

const URL_PATTERN = /(https?:\/\/[^\s]+)/g;

/** Renders text with any http(s) URLs turned into clickable links. */
export function LinkifiedText({ text, className }: { text: string; className?: string }) {
  // Capturing-group split puts matched URLs at odd indices, plain text at even ones.
  const parts = text.split(URL_PATTERN);
  return (
    <span dir="auto" className={className} style={{ unicodeBidi: "isolate" }}>
      {parts.map((part, i) =>
        i % 2 === 1 ? (
          <a
            key={i}
            href={part}
            target="_blank"
            rel="noopener noreferrer"
            className="text-primary underline underline-offset-2"
            onClick={(e) => e.stopPropagation()}
          >
            {part}
          </a>
        ) : (
          <span key={i}>{part}</span>
        )
      )}
    </span>
  );
}
