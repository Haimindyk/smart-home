-- Read-only. Latest measured attempt per job, not all historical retries.
-- Missing legacy measurements are counted separately, never treated as zero.
select status,
  count(*) as jobs,
  count(*) filter (where result->'photoPerformance'->>'version' = '1') as measured_jobs,
  count(*) filter (where status = 'complete' and result->'items' = '[]'::jsonb) as empty_food_results
from public.wellness_ai_jobs
where kind = 'nutrition_photo' and created_at >= now() - interval '14 days'
group by status order by status;

with measured as (
  select status, result->'modelProvenance' as model_config,
    case when jsonb_typeof(result->'photoPerformance'->'totalMs') = 'number'
      then (result->'photoPerformance'->>'totalMs')::numeric end as elapsed_ms
  from public.wellness_ai_jobs
  where kind = 'nutrition_photo' and status in ('complete', 'failed')
    and created_at >= now() - interval '14 days'
    and result->'photoPerformance'->>'version' = '1'
)
select status, model_config, count(elapsed_ms) as measured_jobs,
  percentile_cont(0.5) within group (order by elapsed_ms) as p50_processing_ms,
  percentile_cont(0.95) within group (order by elapsed_ms) as p95_processing_ms,
  max(elapsed_ms) as max_processing_ms
from measured where elapsed_ms >= 0
group by status, model_config order by status;

with measured as (
  select j.status, j.result->'modelProvenance' as model_config,
    stage.key as stage, stage.value->>'outcome' as stage_outcome,
    case when jsonb_typeof(stage.value->'elapsedMs') = 'number'
      then (stage.value->>'elapsedMs')::numeric end as elapsed_ms
  from public.wellness_ai_jobs j
  cross join lateral jsonb_each(case
    when jsonb_typeof(j.result->'photoPerformance'->'stages') = 'object'
      then j.result->'photoPerformance'->'stages' else '{}'::jsonb end) stage
  where j.kind = 'nutrition_photo' and j.status in ('complete', 'failed')
    and j.created_at >= now() - interval '14 days'
    and j.result->'photoPerformance'->>'version' = '1'
)
select status, model_config, stage, stage_outcome, count(elapsed_ms) as samples,
  percentile_cont(0.5) within group (order by elapsed_ms) as p50_ms,
  percentile_cont(0.95) within group (order by elapsed_ms) as p95_ms,
  max(elapsed_ms) as max_ms
from measured where elapsed_ms >= 0
group by status, model_config, stage, stage_outcome
order by status, stage, stage_outcome;
