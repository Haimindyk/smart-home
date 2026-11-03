import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import { beforeAll, afterAll, beforeEach, describe, it, expect } from "vitest";
import {
  makeProgram,
  parsePreferences,
} from "../../supabase/functions/_shared/wellness-core";
const planData = (name: string) => ({
  ...makeProgram(
    {
      plans: [
        {
          name,
          exercises: [
            "Bodyweight_Squat",
            "Glute_Bridge",
            "Push_Up",
            "Dumbbell_Row",
            "Plank",
          ].map((catalogId) => ({ catalogId, sets: 2, reps: 10, rest: 60 })),
        },
      ],
    },
    parsePreferences({
      goal: "muscle",
      experience: "beginner",
      days: [0, 2, 4],
      minutes: 45,
      split: "full_body",
      focus: [],
      equipment: ["bodyweight", "dumbbell"],
      avoid: [],
      notes: "",
    }),
    "2026-11-01",
  ).changes[0].data,
  name,
});
let db: PGlite;
const owner = "11111111-1111-4111-8111-111111111111",
  other = "22222222-2222-4222-8222-222222222222";
const fingerprint = "a".repeat(64);
const claim = async (
  id: string,
  who = owner,
  kind = "nutrition_text",
  fp = fingerprint,
) =>
  (
    await db.query<{ result: { state: string } }>(
      "select public.wellness_claim_job($1,$2,$3,$4) result",
      [id, who, kind, fp],
    )
  ).rows[0].result;
const complete = async (id: string, result: unknown = { items: [] }) =>
  db.query(
    "update public.wellness_ai_jobs set status='complete',result=$2 where id=$1",
    [id, JSON.stringify(result)],
  );
const apply = async (id: string, who = owner) =>
  db.query("select public.wellness_apply_proposal($1,$2)", [id, who]);
beforeAll(async () => {
  db = new PGlite();
  await db.exec(`
 create role anon;create role authenticated;create role service_role bypassrls;
 create schema auth;create schema private;
 create table auth.users(id uuid primary key);
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth,public,private to service_role;grant usage on schema auth,public to authenticated;
 grant execute on function auth.uid() to authenticated;
 create table public.workout_plans(id uuid primary key,owner_user_id uuid not null references auth.users(id),data jsonb not null,version integer not null default 1,last_mutation_id uuid,deleted_at timestamptz,created_at timestamptz default now(),updated_at timestamptz default now());
 create table public.health_profiles(owner_user_id uuid primary key,data jsonb not null,version integer not null default 1);
 create table public.food_catalog(source_key text primary key,source text,data jsonb,attribution text);
 create function public.health_delete_module(p_owner uuid,p_module text) returns void language plpgsql as $$begin
 if p_module not in ('all','nutrition','workouts') then raise exception 'invalid_module';end if;
 if p_module in ('all','workouts') then delete from public.workout_plans where owner_user_id=p_owner;end if;
 if p_module='all' then delete from public.health_profiles where owner_user_id=p_owner;end if;
 end;$$;
 grant all on public.workout_plans,public.health_profiles to service_role;
 insert into auth.users values('${owner}'),('${other}');
 `);
  // Execute the recovered validators/version trigger used by the real application.
  const baseline = readFileSync(
    new URL(
      "../../supabase/recovered-migrations/20261102193842_personal_health.sql",
      import.meta.url,
    ),
    "utf8",
  );
  await db.exec(
    baseline.slice(0, baseline.indexOf("create table public.health_profiles")),
  );
  await db.exec(
    "alter table workout_plans add check(public.health_valid_data('workout_plans',data));alter table food_catalog add check(public.health_valid_food(data));create trigger health_version before update on workout_plans for each row execute function health_version_guard();",
  );
  await db.exec(
    readFileSync(
      new URL(
        "../../supabase/migrations/20261103200306_wellness_ai.sql",
        import.meta.url,
      ),
      "utf8",
    ),
  );
  await db.exec(
    readFileSync(
      new URL(
        "../../supabase/migrations/20261103203820_wellness_training_data.sql",
        import.meta.url,
      ),
      "utf8",
    ),
  );
}, 30000);
afterAll(async () => db?.close());
beforeEach(async () => {
  await db.exec(
    "reset role;truncate public.wellness_training_examples,public.wellness_training_consents;truncate public.wellness_ai_jobs cascade;truncate private.wellness_ai_daily_usage,public.workout_plans,public.health_profiles,public.wellness_exercise_illustrations;",
  );
});
describe("real Postgres quota, authorization and transactional proposals", () => {
  it("deduplicates completed requests without charging the daily budget again", async () => {
    const id = crypto.randomUUID();
    expect((await claim(id)).state).toBe("claimed");
    expect((await claim(id)).state).toBe("busy");
    await complete(id);
    expect((await claim(id)).state).toBe("complete");
    const usage = await db.query<{ calls: Record<string, number> }>(
      "select calls from private.wellness_ai_daily_usage",
    );
    expect(usage.rows[0].calls.nutrition_text).toBe(1);
  });
  it("rejects reuse by another owner or with different content", async () => {
    const id = crypto.randomUUID();
    await claim(id);
    await expect(claim(id, other)).rejects.toThrow("request_conflict");
    await expect(
      claim(id, owner, "nutrition_text", "b".repeat(64)),
    ).rejects.toThrow("request_conflict");
  });
  it("enforces per-user and account-wide free compute reservations", async () => {
    for (let i = 0; i < 20; i++) {
      const id = crypto.randomUUID();
      expect((await claim(id)).state).toBe("claimed");
      await complete(id);
    }
    expect((await claim(crypto.randomUUID())).state).toBe("quota");
    await db.exec(
      "update private.wellness_ai_daily_usage set reserved_neurons=7900",
    );
    expect((await claim(crypto.randomUUID(), other)).state).toBe("quota");
  });
  it("allows at most two active jobs globally and one per owner", async () => {
    await claim(crypto.randomUUID());
    expect((await claim(crypto.randomUUID())).state).toBe("busy");
    expect((await claim(crypto.randomUUID(), other)).state).toBe("claimed");
  });
  it("keeps private results isolated and blocks direct authenticated writes/RPCs", async () => {
    const id = crypto.randomUUID();
    await claim(id);
    await complete(id);
    await db.query("select set_config('request.jwt.claim.sub',$1,false)", [
      other,
    ]);
    await db.exec("set role authenticated");
    expect(
      (await db.query("select * from public.wellness_ai_jobs")).rows,
    ).toHaveLength(0);
    await expect(
      db.query("select public.wellness_claim_job($1,$2,$3,$4)", [
        crypto.randomUUID(),
        other,
        "coach",
        fingerprint,
      ]),
    ).rejects.toThrow("permission denied");
    await expect(
      db.query(
        "update public.wellness_ai_jobs set status='applied' where id=$1",
        [id],
      ),
    ).rejects.toThrow("permission denied");
    await db.exec("reset role");
  });
  it("rolls back every change when any plan version is stale", async () => {
    const a = "00000000-0000-4000-8000-000000000001",
      b = "00000000-0000-4000-8000-000000000002",
      job = crypto.randomUUID();
    for (const id of [a, b])
      await db.query(
        "insert into workout_plans(id,owner_user_id,data)values($1,$2,$3)",
        [id, owner, JSON.stringify(planData("before"))],
      );
    await claim(job, owner, "coach");
    await complete(job, {
      changes: [
        { id: a, expectedVersion: 1, data: planData("after") },
        { id: b, expectedVersion: 99, data: planData("after") },
      ],
    });
    await expect(apply(job)).rejects.toThrow("version_conflict");
    expect(
      (
        await db.query<{ version: number; data: { name: string } }>(
          "select version,data from workout_plans",
        )
      ).rows.every((p) => p.version === 1 && p.data.name === "before"),
    ).toBe(true);
    expect(
      (await db.query("select * from wellness_plan_versions")).rows,
    ).toHaveLength(0);
  });
  it("applies a proposal once and preserves the prior version for undo", async () => {
    const id = crypto.randomUUID(),
      job = crypto.randomUUID();
    await db.query(
      "insert into workout_plans(id,owner_user_id,data)values($1,$2,$3)",
      [id, owner, JSON.stringify(planData("before"))],
    );
    await claim(job, owner, "coach");
    await complete(job, {
      changes: [{ id, expectedVersion: 1, data: planData("after") }],
    });
    await expect(apply(job, other)).rejects.toThrow("not_found");
    await apply(job);
    await apply(job);
    expect(
      (await db.query<{ version: number }>("select version from workout_plans"))
        .rows[0].version,
    ).toBe(2);
    const history = (
      await db.query<{ previous_data: { name: string } }>(
        "select previous_data from wellness_plan_versions",
      )
    ).rows;
    expect(history).toHaveLength(1);
    expect(history[0].previous_data.name).toBe("before");
  });
  it("cannot modify a different owner plan, even from a fabricated stored proposal", async () => {
    const id = crypto.randomUUID(),
      job = crypto.randomUUID();
    await db.query(
      "insert into workout_plans(id,owner_user_id,data)values($1,$2,$3)",
      [id, other, JSON.stringify(planData("private"))],
    );
    await claim(job, owner, "coach");
    await complete(job, {
      changes: [{ id, expectedVersion: 1, data: planData("after") }],
    });
    await expect(apply(job)).rejects.toThrow("version_conflict");
  });
  it("deleting workouts clears AI history and images while retaining nutrition jobs", async () => {
    const coach = crypto.randomUUID(),
      meal = crypto.randomUUID();
    await claim(coach, owner, "coach");
    await complete(coach, {
      changes: [
        {
          id: crypto.randomUUID(),
          expectedVersion: null,
          data: planData("new"),
        },
      ],
    });
    await apply(coach);
    await claim(meal);
    await complete(meal);
    await db.query(
      "insert into wellness_exercise_illustrations(owner_user_id,exercise_id,image_path)values($1,$2,$3)",
      [owner, "Push_Up", `${owner}/image.jpg`],
    );
    await db.query("select health_delete_module($1,'workouts')", [owner]);
    expect(
      (await db.query("select * from wellness_plan_versions")).rows,
    ).toHaveLength(0);
    expect(
      (await db.query("select * from wellness_exercise_illustrations")).rows,
    ).toHaveLength(0);
    expect((await db.query("select id from wellness_ai_jobs")).rows).toEqual([
      { id: meal },
    ]);
  });
  it("the restricted service role can claim and apply a validated program", async () => {
    await db.exec("set role service_role");
    const job = crypto.randomUUID();
    expect((await claim(job, owner, "coach")).state).toBe("claimed");
    await complete(job, {
      changes: [
        {
          id: crypto.randomUUID(),
          expectedVersion: null,
          data: planData("service plan"),
        },
      ],
    });
    await apply(job);
    expect(
      (await db.query("select * from wellness_plan_versions")).rows,
    ).toHaveLength(1);
    await db.exec("reset role");
  });
  it("a deleted or cross-owner job cannot recreate an illustration after inference completes", async () => {
    const job = crypto.randomUUID();
    await claim(job, owner, "illustration");
    await expect(
      db.query("select wellness_publish_illustration($1,$2,$3,$4)", [
        job,
        other,
        "Push_Up",
        `${other}/image.jpg`,
      ]),
    ).rejects.toThrow("request_conflict");
    await db.query("select wellness_publish_illustration($1,$2,$3,$4)", [
      job,
      owner,
      "Push_Up",
      `${owner}/image.jpg`,
    ]);
    await db.query("select health_delete_module($1,'workouts')", [owner]);
    await expect(
      db.query("select wellness_publish_illustration($1,$2,$3,$4)", [
        job,
        owner,
        "Push_Up",
        `${owner}/late.jpg`,
      ]),
    ).rejects.toThrow("request_conflict");
    expect(
      (await db.query("select * from wellness_exercise_illustrations")).rows,
    ).toHaveLength(0);
  });
  it("training consent is separate and revocation removes submitted examples", async () => {
    const submit = () =>
      db.query(
        "select wellness_training_submit($1,'nutrition_text',$2,$3,null)",
        [
          owner,
          crypto.randomUUID(),
          JSON.stringify({
            input: { description: "meal" },
            target: { items: [] },
          }),
        ],
      );
    await expect(submit()).rejects.toThrow("training_consent_required");
    await db.query("select wellness_training_consent($1,true)", [owner]);
    await submit();
    expect(
      (await db.query("select * from wellness_training_examples")).rows,
    ).toHaveLength(1);
    await db.query("select wellness_training_consent($1,false)", [owner]);
    expect(
      (await db.query("select * from wellness_training_examples")).rows,
    ).toHaveLength(0);
    await expect(submit()).rejects.toThrow("training_consent_required");
  });
  it("training examples are isolated and clients cannot grant themselves consent by SQL", async () => {
    await db.query("select wellness_training_consent($1,true)", [owner]);
    await db.query(
      "select wellness_training_submit($1,'coach_program',$2,'{}',null)",
      [owner, crypto.randomUUID()],
    );
    await db.query("select set_config('request.jwt.claim.sub',$1,false)", [
      other,
    ]);
    await db.exec("set role authenticated");
    expect(
      (await db.query("select * from wellness_training_examples")).rows,
    ).toHaveLength(0);
    await expect(
      db.query("select wellness_training_consent($1,true)", [other]),
    ).rejects.toThrow("permission denied");
    await db.exec("reset role");
  });
  it("module deletion removes corresponding training snapshots and all deletion removes consent", async () => {
    await db.query("select wellness_training_consent($1,true)", [owner]);
    for (const task of ["coach_program", "nutrition_text"])
      await db.query("select wellness_training_submit($1,$2,$3,'{}',null)", [
        owner,
        task,
        crypto.randomUUID(),
      ]);
    await db.query("select health_delete_module($1,'workouts')", [owner]);
    expect(
      (await db.query("select task from wellness_training_examples")).rows,
    ).toEqual([{ task: "nutrition_text" }]);
    await db.query("select health_delete_module($1,'all')", [owner]);
    expect(
      (await db.query("select * from wellness_training_examples")).rows,
    ).toHaveLength(0);
    expect(
      (await db.query("select * from wellness_training_consents")).rows,
    ).toHaveLength(0);
  });
  it("own adapters reserve a conservative budget and completed retries are free", async () => {
    const job = crypto.randomUUID();
    await db.query(
      "select wellness_claim_owned_job($1,$2,'nutrition_text',$3)",
      [job, owner, fingerprint],
    );
    expect(
      (
        await db.query<{ reserved_neurons: number }>(
          "select reserved_neurons from private.wellness_ai_daily_usage",
        )
      ).rows[0].reserved_neurons,
    ).toBe(1600);
    await complete(job);
    await db.query(
      "select wellness_claim_owned_job($1,$2,'nutrition_text',$3)",
      [job, owner, fingerprint],
    );
    expect(
      (
        await db.query<{ reserved_neurons: number }>(
          "select reserved_neurons from private.wellness_ai_daily_usage",
        )
      ).rows[0].reserved_neurons,
    ).toBe(1600);
  });
});
