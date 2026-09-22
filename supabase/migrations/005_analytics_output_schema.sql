-- Analytics output schema.
-- Event ingestion stays in public.analytics_events for Sprint 2 so Kotlin/Flutter
-- can use the same PostgREST contract without exposing a second API schema.

create schema if not exists analytics;

create table if not exists analytics.bq_results (
  id bigint generated always as identity primary key,
  bq_key text not null,
  computed_at timestamptz not null default now(),
  window_start timestamptz,
  window_end timestamptz,
  payload jsonb not null default '{}'::jsonb
);

create index if not exists bq_results_key_time_idx
on analytics.bq_results (bq_key, computed_at desc);

create table if not exists analytics.user_features (
  user_id uuid primary key references auth.users(id) on delete cascade,
  preferred_categories text[] not null default '{}',
  avg_completed_duration_minutes numeric,
  acceptance_rate numeric,
  completion_rate numeric,
  last_computed_at timestamptz not null default now()
);

revoke all on schema analytics from anon, authenticated;
revoke all on all tables in schema analytics from anon, authenticated;
