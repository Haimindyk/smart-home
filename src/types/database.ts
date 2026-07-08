export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      activity_log: {
        Row: {
          action: string
          actor_id: string | null
          created_at: string
          entity_id: string
          entity_type: string
          id: string
          seq: number
          summary: string | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          entity_id: string
          entity_type: string
          id?: string
          seq?: never
          summary?: string | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          entity_id?: string
          entity_type?: string
          id?: string
          seq?: never
          summary?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "activity_log_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
        ]
      }
      attachments: {
        Row: {
          chore_id: string | null
          created_at: string
          created_by: string | null
          file_name: string
          height: number | null
          id: string
          kind: string
          mime_type: string | null
          size_bytes: number | null
          storage_path: string
          task_id: string | null
          width: number | null
        }
        Insert: {
          chore_id?: string | null
          created_at?: string
          created_by?: string | null
          file_name: string
          height?: number | null
          id?: string
          kind?: string
          mime_type?: string | null
          size_bytes?: number | null
          storage_path: string
          task_id?: string | null
          width?: number | null
        }
        Update: {
          chore_id?: string | null
          created_at?: string
          created_by?: string | null
          file_name?: string
          height?: number | null
          id?: string
          kind?: string
          mime_type?: string | null
          size_bytes?: number | null
          storage_path?: string
          task_id?: string | null
          width?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "attachments_chore_id_fkey"
            columns: ["chore_id"]
            isOneToOne: false
            referencedRelation: "chores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attachments_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attachments_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
        ]
      }
      chore_completions: {
        Row: {
          chore_id: string
          completed_at: string
          completed_by: string
          created_at: string
          due_at: string
          id: string
        }
        Insert: {
          chore_id: string
          completed_at?: string
          completed_by: string
          created_at?: string
          due_at: string
          id?: string
        }
        Update: {
          chore_id?: string
          completed_at?: string
          completed_by?: string
          created_at?: string
          due_at?: string
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "chore_completions_chore_id_fkey"
            columns: ["chore_id"]
            isOneToOne: false
            referencedRelation: "chores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chore_completions_completed_by_fkey"
            columns: ["completed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
        ]
      }
      chores: {
        Row: {
          anchor_date: string
          assignee_kind: string
          assignee_member_id: string | null
          assignee_member_ids: string[]
          created_at: string
          created_by: string | null
          custom_cron: string | null
          deleted_at: string | null
          emoji: string | null
          freq: string
          id: string
          interval_n: number
          month_day: number | null
          next_due_at: string
          notes: string | null
          position: string
          section_id: string
          title: string
          updated_at: string
          updated_by: string | null
          weekdays: number[] | null
        }
        Insert: {
          anchor_date?: string
          assignee_kind?: string
          assignee_member_id?: string | null
          assignee_member_ids?: string[]
          created_at?: string
          created_by?: string | null
          custom_cron?: string | null
          deleted_at?: string | null
          emoji?: string | null
          freq: string
          id?: string
          interval_n?: number
          month_day?: number | null
          next_due_at?: string
          notes?: string | null
          position: string
          section_id: string
          title: string
          updated_at?: string
          updated_by?: string | null
          weekdays?: number[] | null
        }
        Update: {
          anchor_date?: string
          assignee_kind?: string
          assignee_member_id?: string | null
          assignee_member_ids?: string[]
          created_at?: string
          created_by?: string | null
          custom_cron?: string | null
          deleted_at?: string | null
          emoji?: string | null
          freq?: string
          id?: string
          interval_n?: number
          month_day?: number | null
          next_due_at?: string
          notes?: string | null
          position?: string
          section_id?: string
          title?: string
          updated_at?: string
          updated_by?: string | null
          weekdays?: number[] | null
        }
        Relationships: [
          {
            foreignKeyName: "chores_assignee_member_id_fkey"
            columns: ["assignee_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chores_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chores_section_id_fkey"
            columns: ["section_id"]
            isOneToOne: false
            referencedRelation: "sections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chores_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
        ]
      }
      family_events: {
        Row: {
          created_at: string
          created_by: string | null
          deleted_at: string | null
          emoji: string | null
          event_date: string
          id: string
          kind: string
          last_notified_on: string | null
          notes: string | null
          recurrence: string
          title: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          emoji?: string | null
          event_date: string
          id?: string
          kind?: string
          last_notified_on?: string | null
          notes?: string | null
          recurrence?: string
          title: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          emoji?: string | null
          event_date?: string
          id?: string
          kind?: string
          last_notified_on?: string | null
          notes?: string | null
          recurrence?: string
          title?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "family_events_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "family_events_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
        ]
      }
      members: {
        Row: {
          avatar_emoji: string | null
          avatar_photo_url: string | null
          color: string
          created_at: string
          display_name: string
          email: string
          id: string
          locale: string
          pin: string | null
          updated_at: string
          user_id: string | null
        }
        Insert: {
          avatar_emoji?: string | null
          avatar_photo_url?: string | null
          color?: string
          created_at?: string
          display_name: string
          email: string
          id?: string
          locale?: string
          pin?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          avatar_emoji?: string | null
          avatar_photo_url?: string | null
          color?: string
          created_at?: string
          display_name?: string
          email?: string
          id?: string
          locale?: string
          pin?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Relationships: []
      }
      notification_prefs: {
        Row: {
          member_id: string
          on_create: boolean
          on_complete: boolean
          on_assigned_me: boolean
          on_shopping: boolean
          on_due: boolean
          on_broadcast: boolean
          muted: boolean
          updated_at: string
        }
        Insert: {
          member_id: string
          on_create?: boolean
          on_complete?: boolean
          on_assigned_me?: boolean
          on_shopping?: boolean
          on_due?: boolean
          on_broadcast?: boolean
          muted?: boolean
          updated_at?: string
        }
        Update: {
          member_id?: string
          on_create?: boolean
          on_complete?: boolean
          on_assigned_me?: boolean
          on_shopping?: boolean
          on_due?: boolean
          on_broadcast?: boolean
          muted?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_prefs_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
        ]
      }
      push_subscriptions: {
        Row: {
          id: string
          member_id: string | null
          endpoint: string
          p256dh: string
          auth: string
          user_agent: string | null
          created_at: string
        }
        Insert: {
          id?: string
          member_id?: string | null
          endpoint: string
          p256dh: string
          auth: string
          user_agent?: string | null
          created_at?: string
        }
        Update: {
          id?: string
          member_id?: string | null
          endpoint?: string
          p256dh?: string
          auth?: string
          user_agent?: string | null
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "push_subscriptions_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
        ]
      }
      sections: {
        Row: {
          color: string | null
          created_at: string
          created_by: string | null
          deleted_at: string | null
          description: string | null
          emoji: string | null
          id: string
          kind: string
          name: string
          position: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          color?: string | null
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          description?: string | null
          emoji?: string | null
          id?: string
          kind?: string
          name: string
          position: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          color?: string | null
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          description?: string | null
          emoji?: string | null
          id?: string
          kind?: string
          name?: string
          position?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sections_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sections_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
        ]
      }
      tasks: {
        Row: {
          assignee_kind: string
          assignee_member_id: string | null
          assignee_member_ids: string[]
          brand: string | null
          completed_at: string | null
          completed_by: string | null
          created_at: string
          created_by: string | null
          currency: string | null
          deleted_at: string | null
          detected_links: string[]
          due_at: string | null
          due_notified_at: string | null
          emoji: string | null
          id: string
          image_url: string | null
          is_completed: boolean
          is_note: boolean
          notes: string | null
          parent_task_id: string | null
          position: string
          price: number | null
          priority: number | null
          quantity: number | null
          recurrence: Json | null
          section_id: string
          tags: string[]
          title: string
          unit: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          assignee_kind?: string
          assignee_member_id?: string | null
          assignee_member_ids?: string[]
          brand?: string | null
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          deleted_at?: string | null
          detected_links?: string[]
          due_at?: string | null
          due_notified_at?: string | null
          emoji?: string | null
          id?: string
          image_url?: string | null
          is_completed?: boolean
          is_note?: boolean
          notes?: string | null
          parent_task_id?: string | null
          position: string
          price?: number | null
          priority?: number | null
          quantity?: number | null
          recurrence?: Json | null
          section_id: string
          tags?: string[]
          title?: string
          unit?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          assignee_kind?: string
          assignee_member_id?: string | null
          assignee_member_ids?: string[]
          brand?: string | null
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          deleted_at?: string | null
          detected_links?: string[]
          due_at?: string | null
          due_notified_at?: string | null
          emoji?: string | null
          id?: string
          image_url?: string | null
          is_completed?: boolean
          is_note?: boolean
          notes?: string | null
          parent_task_id?: string | null
          position?: string
          price?: number | null
          priority?: number | null
          quantity?: number | null
          recurrence?: Json | null
          section_id?: string
          tags?: string[]
          title?: string
          unit?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tasks_assignee_member_id_fkey"
            columns: ["assignee_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_completed_by_fkey"
            columns: ["completed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_parent_task_id_fkey"
            columns: ["parent_task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_section_id_fkey"
            columns: ["section_id"]
            isOneToOne: false
            referencedRelation: "sections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      complete_chore: {
        Args: { p_chore_id: string; p_completed_by: string }
        Returns: undefined
      }
      is_member: { Args: Record<string, never>; Returns: boolean }
      restore_task: {
        Args: { p_task_id: string } | { p_actor_id?: string; p_task_id: string }
        Returns: undefined
      }
      soft_delete_task: {
        Args: { p_task_id: string } | { p_actor_id?: string; p_task_id: string }
        Returns: undefined
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">
type DefaultSchema = DatabaseWithoutInternals["public"]

export type Tables<T extends keyof DefaultSchema["Tables"]> = DefaultSchema["Tables"][T]["Row"]
export type TablesInsert<T extends keyof DefaultSchema["Tables"]> = DefaultSchema["Tables"][T]["Insert"]
export type TablesUpdate<T extends keyof DefaultSchema["Tables"]> = DefaultSchema["Tables"][T]["Update"]
