-- Sidequests Sprint 2 foundation schema
-- Shared backend for Kotlin + Flutter clients.

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  interests text[] not null default '{}',
  preferred_difficulty text not null default 'easy'
    check (preferred_difficulty in ('easy', 'medium', 'hard')),
  typical_time_minutes integer not null default 30
    check (typical_time_minutes between 5 and 1440),
  budget_max numeric(10,2) not null default 20
    check (budget_max >= 0),
  social_level text not null default 'solo'
    check (social_level in ('solo', 'social', 'group')),
  location_mode text not null default 'all'
    check (location_mode in ('all', 'gps', 'anywhere')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.quests (
  id text primary key,
  title text not null,
  description text not null default '',
  category text not null,
  emoji text,
  duration_minutes integer not null check (duration_minutes > 0),
  estimated_cost numeric(10,2) not null default 0 check (estimated_cost >= 0),
  difficulty text not null check (difficulty in ('easy', 'medium', 'hard')),
  location_mode text not null check (location_mode in ('gps', 'anywhere')),
  social_level text not null check (social_level in ('solo', 'social', 'group')),
  location_name text,
  latitude double precision check (latitude is null or latitude between -90 and 90),
  longitude double precision check (longitude is null or longitude between -180 and 180),
  tags text[] not null default '{}',
  is_new boolean not null default false,
  is_sponsored boolean not null default false,
  sponsor_name text,
  is_group boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quests_location_coordinates_check check (
    location_mode = 'anywhere'
    or (latitude is not null and longitude is not null)
  )
);

create table public.quest_steps (
  id bigint generated always as identity primary key,
  quest_id text not null references public.quests(id) on delete cascade,
  step_order integer not null check (step_order >= 0),
  title text not null,
  description text not null default '',
  verification_type text not null default 'none'
    check (verification_type in ('none', 'photo', 'location', 'photo_and_location')),
  unique (quest_id, step_order)
);

create table public.user_quests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  quest_id text not null references public.quests(id) on delete restrict,
  status text not null default 'accepted'
    check (status in ('accepted', 'in_progress', 'completed', 'abandoned', 'skipped')),
  current_step integer not null default 0 check (current_step >= 0),
  completed_steps integer[] not null default '{}',
  abandon_reason text,
  rating integer check (rating is null or rating between 1 and 5),
  feedback_tags text[] not null default '{}',
  photo_proof_path text,
  accepted_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  abandoned_at timestamptz,
  updated_at timestamptz not null default now()
);

create table public.analytics_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid,
  event_type text not null,
  quest_id text references public.quests(id) on delete set null,
  category text,
  occurred_at timestamptz not null default now(),
  available_minutes integer check (available_minutes is null or available_minutes >= 0),
  social_level text check (social_level is null or social_level in ('solo', 'social', 'group')),
  latitude double precision check (latitude is null or latitude between -90 and 90),
  longitude double precision check (longitude is null or longitude between -180 and 180),
  weather_code integer,
  time_of_day text,
  location_mode text check (location_mode is null or location_mode in ('all', 'gps', 'anywhere')),
  quest_duration_minutes integer check (quest_duration_minutes is null or quest_duration_minutes > 0),
  quest_difficulty text check (quest_difficulty is null or quest_difficulty in ('easy', 'medium', 'hard')),
  estimated_cost numeric(10,2) check (estimated_cost is null or estimated_cost >= 0),
  distance_meters integer check (distance_meters is null or distance_meters >= 0),
  metadata jsonb not null default '{}'::jsonb
);

create index user_quests_user_updated_idx on public.user_quests(user_id, updated_at desc);
create index user_quests_user_quest_status_idx on public.user_quests(user_id, quest_id, status);
create index analytics_events_user_time_idx on public.analytics_events(user_id, occurred_at desc);
create index analytics_events_type_time_idx on public.analytics_events(event_type, occurred_at desc);
create index analytics_events_quest_time_idx on public.analytics_events(quest_id, occurred_at desc) where quest_id is not null;
create index quests_active_category_idx on public.quests(is_active, category);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger user_preferences_set_updated_at
before update on public.user_preferences
for each row execute function public.set_updated_at();

create trigger quests_set_updated_at
before update on public.quests
for each row execute function public.set_updated_at();

create trigger user_quests_set_updated_at
before update on public.user_quests
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'display_name', ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), '')
    )
  )
  on conflict (id) do nothing;

  insert into public.user_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.user_preferences enable row level security;
alter table public.quests enable row level security;
alter table public.quest_steps enable row level security;
alter table public.user_quests enable row level security;
alter table public.analytics_events enable row level security;

revoke all on public.profiles from anon;
revoke all on public.user_preferences from anon;
revoke all on public.quests from anon;
revoke all on public.quest_steps from anon;
revoke all on public.user_quests from anon;
revoke all on public.analytics_events from anon;

grant select, insert, update on public.profiles to authenticated;
grant select, insert, update on public.user_preferences to authenticated;
grant select on public.quests to authenticated;
grant select on public.quest_steps to authenticated;
grant select, insert, update on public.user_quests to authenticated;
grant select, insert on public.analytics_events to authenticated;

grant usage, select on sequence public.quest_steps_id_seq to authenticated;
grant usage, select on sequence public.analytics_events_id_seq to authenticated;

create policy "profiles_select_own"
on public.profiles for select to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = id);

create policy "profiles_insert_own"
on public.profiles for insert to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = id);

create policy "profiles_update_own"
on public.profiles for update to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = id)
with check ((select auth.uid()) is not null and (select auth.uid()) = id);

create policy "preferences_select_own"
on public.user_preferences for select to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "preferences_insert_own"
on public.user_preferences for insert to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "preferences_update_own"
on public.user_preferences for update to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "quests_select_active"
on public.quests for select to authenticated
using (is_active = true);

create policy "quest_steps_select_authenticated"
on public.quest_steps for select to authenticated
using (true);

create policy "user_quests_select_own"
on public.user_quests for select to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_quests_insert_own"
on public.user_quests for insert to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_quests_update_own"
on public.user_quests for update to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "analytics_events_select_own"
on public.analytics_events for select to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "analytics_events_insert_own"
on public.analytics_events for insert to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);
