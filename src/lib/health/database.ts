import type { Database } from "@/types/database";
import type { HealthGeneratedDatabase } from "@/types/health-database.generated";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import type { HealthTable, Payload } from "./model";
type GeneratedTables = HealthGeneratedDatabase["public"]["Tables"];
// Columns/defaults come from PostgreSQL; the JSON aggregate is narrowed by the
// same runtime schemas used before every local write.
type HealthTables = {
  [T in HealthTable]: {
    Row: Omit<GeneratedTables[T]["Row"], "data"> & {
      data: Payload<HealthTable>;
    };
    Insert: Omit<GeneratedTables[T]["Insert"], "data"> & {
      data: Payload<HealthTable>;
    };
    Update: Omit<GeneratedTables[T]["Update"], "data"> & {
      data?: Payload<HealthTable>;
    };
    Relationships: [];
  };
};
export type HealthDatabase = Omit<Database, "public"> & {
  public: Omit<Database["public"], "Tables"> & {
    Tables: Database["public"]["Tables"] & HealthTables;
  };
};
// Reuse the browser singleton so auth, refresh and sign-out remain consistent.
export function healthClient() {
  return createClient() as unknown as SupabaseClient<HealthDatabase>;
}
