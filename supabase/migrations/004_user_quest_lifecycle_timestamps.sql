-- Keep quest lifecycle timestamps authoritative in the shared backend.
-- Kotlin and Flutter should update status/progress; Postgres owns transition timestamps.

create or replace function public.set_user_quest_lifecycle_timestamps()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'in_progress'
     and old.status is distinct from 'in_progress'
     and new.started_at is null then
    new.started_at = now();
  end if;

  if new.status = 'completed'
     and old.status is distinct from 'completed'
     and new.completed_at is null then
    new.completed_at = now();
  end if;

  if new.status = 'abandoned'
     and old.status is distinct from 'abandoned'
     and new.abandoned_at is null then
    new.abandoned_at = now();
  end if;

  return new;
end;
$$;

create trigger user_quests_set_lifecycle_timestamps
before update on public.user_quests
for each row
execute function public.set_user_quest_lifecycle_timestamps();
