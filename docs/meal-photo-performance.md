# Photo processing latency

The photo handler stores `result.photoPerformance` version 1 in the existing
owner-scoped `wellness_ai_jobs` result. It records elapsed milliseconds for private
image download/decoding, vision, normalization (including parsing/validation), and
catalog matching when that stage is needed. Calls and existing validation rules
remain unchanged. Failed stages retain their duration and outcome; no image,
observation, description, owner identifier or error contents enter this object.
Model configuration uses the existing non-secret `modelProvenance` fields.

`totalMs` is **server photo processing**, beginning after authentication and job
claim and ending after validation/catalog matching (or the caught failure).
It excludes client upload, auth/claim, result persistence and diary save. It is
not end-to-end camera latency, a predicted wait time, or an accuracy metric.
Completion-write failures can have all processing stages complete while the job
status is failed. A snapshot freezes the processing interval before persistence.

Run the read-only [aggregate queries](../scripts/wellness-photo-performance.sql)
with an authorized database operator account. They return counts and timings by
job status, model configuration and stage, with p50/p95 and maxima. Do not expose
these operator queries as a public application endpoint. Legacy jobs without
measurements remain unmeasured rather than becoming zero-duration samples.
An absent catalog stage means it was skipped, not that it took zero milliseconds.
Completed processing can still return no food; the coverage query counts those
empty results separately rather than calling them successful recognitions.

Each job stores the **latest attempt**; retrying a failed job replaces its timing.
A cached successful response retains its original timing instead of pretending a
model ran again. Thus these aggregates diagnose processing, but do not count all
historical retries or replace the complete-attempt offline benchmark. Model
comparisons still need the same real image inputs and ingredient/weight scoring.

On 2026-11-14, a read-only check found 7 completed photo jobs from the previous
14 days. Their median database record lifetime was 23.10 seconds and maximum
44.59 seconds. Those older created/updated intervals lack stage breakdowns and
may include retries; they are not a clean inference benchmark. Stage measurements
begin with subsequent real requests after this change is merged and deployed.
No performance speedup or improved model accuracy is claimed by instrumentation.
