// Generated from PostgreSQL by scripts/generate-health-types.py. Do not edit.
import type { Json } from "./database";
export type HealthGeneratedDatabase = {
  public: {
    Tables: {
      health_profiles: {
        Row: {
          id: string;
          owner_user_id: string;
          data: Json;
          version: number;
          last_mutation_id: string;
          created_at: string;
          updated_at: string;
          deleted_at: string | null;
        };
        Insert: {
          id?: string;
          owner_user_id?: string;
          data: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Update: {
          id?: string;
          owner_user_id?: string;
          data?: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Relationships: [];
      };
      nutrition_goals: {
        Row: {
          id: string;
          owner_user_id: string;
          data: Json;
          version: number;
          last_mutation_id: string;
          created_at: string;
          updated_at: string;
          deleted_at: string | null;
        };
        Insert: {
          id?: string;
          owner_user_id?: string;
          data: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Update: {
          id?: string;
          owner_user_id?: string;
          data?: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Relationships: [];
      };
      personal_foods: {
        Row: {
          id: string;
          owner_user_id: string;
          data: Json;
          version: number;
          last_mutation_id: string;
          created_at: string;
          updated_at: string;
          deleted_at: string | null;
        };
        Insert: {
          id?: string;
          owner_user_id?: string;
          data: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Update: {
          id?: string;
          owner_user_id?: string;
          data?: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Relationships: [];
      };
      recipes: {
        Row: {
          id: string;
          owner_user_id: string;
          data: Json;
          version: number;
          last_mutation_id: string;
          created_at: string;
          updated_at: string;
          deleted_at: string | null;
        };
        Insert: {
          id?: string;
          owner_user_id?: string;
          data: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Update: {
          id?: string;
          owner_user_id?: string;
          data?: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Relationships: [];
      };
      meals: {
        Row: {
          id: string;
          owner_user_id: string;
          data: Json;
          version: number;
          last_mutation_id: string;
          created_at: string;
          updated_at: string;
          deleted_at: string | null;
        };
        Insert: {
          id?: string;
          owner_user_id?: string;
          data: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Update: {
          id?: string;
          owner_user_id?: string;
          data?: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Relationships: [];
      };
      water_logs: {
        Row: {
          id: string;
          owner_user_id: string;
          data: Json;
          version: number;
          last_mutation_id: string;
          created_at: string;
          updated_at: string;
          deleted_at: string | null;
        };
        Insert: {
          id?: string;
          owner_user_id?: string;
          data: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Update: {
          id?: string;
          owner_user_id?: string;
          data?: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Relationships: [];
      };
      weight_logs: {
        Row: {
          id: string;
          owner_user_id: string;
          data: Json;
          version: number;
          last_mutation_id: string;
          created_at: string;
          updated_at: string;
          deleted_at: string | null;
        };
        Insert: {
          id?: string;
          owner_user_id?: string;
          data: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Update: {
          id?: string;
          owner_user_id?: string;
          data?: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Relationships: [];
      };
      workout_plans: {
        Row: {
          id: string;
          owner_user_id: string;
          data: Json;
          version: number;
          last_mutation_id: string;
          created_at: string;
          updated_at: string;
          deleted_at: string | null;
        };
        Insert: {
          id?: string;
          owner_user_id?: string;
          data: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Update: {
          id?: string;
          owner_user_id?: string;
          data?: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Relationships: [];
      };
      workout_sessions: {
        Row: {
          id: string;
          owner_user_id: string;
          data: Json;
          version: number;
          last_mutation_id: string;
          created_at: string;
          updated_at: string;
          deleted_at: string | null;
        };
        Insert: {
          id?: string;
          owner_user_id?: string;
          data: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Update: {
          id?: string;
          owner_user_id?: string;
          data?: Json;
          version?: number;
          last_mutation_id?: string;
          created_at?: string;
          updated_at?: string;
          deleted_at?: string | null;
        };
        Relationships: [];
      };
      food_catalog: {
        Row: {
          source_key: string;
          source: string;
          data: Json;
          attribution: string;
          updated_at: string;
        };
        Insert: {
          source_key: string;
          source: string;
          data: Json;
          attribution: string;
          updated_at?: string;
        };
        Update: {
          source_key?: string;
          source?: string;
          data?: Json;
          attribution?: string;
          updated_at?: string;
        };
        Relationships: [];
      };
      nutrition_analyses: {
        Row: {
          id: string;
          owner_user_id: string;
          image_path: string;
          status: string;
          result: Json | null;
          model: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id: string;
          owner_user_id?: string;
          image_path: string;
          status: string;
          result?: Json | null;
          model?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          owner_user_id?: string;
          image_path?: string;
          status?: string;
          result?: Json | null;
          model?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Relationships: [];
      };
    };
  };
};
