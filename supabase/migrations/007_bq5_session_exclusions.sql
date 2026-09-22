-- Make "Not for me" an immediate session-level exclusion for BQ5.
-- Both Kotlin and Flutter can pass quest ids already rejected in the current session.

drop function if exists public.recommend_quests(integer, text, text[], text, integer);

create or replace function public.recommend_quests(
  p_available_minutes integer,
  p_social_level text,
  p_interests text[] default '{}'::text[],
  p_location_mode text default 'all',
  p_excluded_quest_ids text[] default '{}'::text[],
  p_limit integer default 3
)
returns table (
  quest_id text,
  score numeric,
  time_match boolean,
  interest_match boolean,
  social_match boolean,
  location_match boolean,
  history_penalty numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
  with history as (
    select
      uq.quest_id,
      count(*) filter (where uq.status = 'completed') as completed_count,
      count(*) filter (where uq.status = 'abandoned') as abandoned_count,
      bool_or(uq.status in ('accepted', 'in_progress')) as active_now
    from public.user_quests uq
    where uq.user_id = auth.uid()
    group by uq.quest_id
  ),
  skips as (
    select
      ae.quest_id,
      count(*) as skip_count
    from public.analytics_events ae
    where ae.user_id = auth.uid()
      and ae.event_type = 'recommendation_skipped'
      and ae.quest_id is not null
    group by ae.quest_id
  ),
  features as (
    select
      q.id as quest_id,
      (q.duration_minutes <= greatest(coalesce(p_available_minutes, 0), 0)) as time_match,
      (
        coalesce(cardinality(p_interests), 0) = 0
        or exists (
          select 1
          from unnest(coalesce(p_interests, '{}'::text[])) as interest(value)
          where lower(interest.value) = lower(q.category)
             or lower(interest.value) = any(q.tags)
        )
      ) as interest_match,
      (
        nullif(p_social_level, '') is null
        or q.social_level = lower(p_social_level)
      ) as social_match,
      (
        coalesce(nullif(p_location_mode, ''), 'all') = 'all'
        or q.location_mode = lower(p_location_mode)
      ) as location_match,
      (
        coalesce(h.abandoned_count, 0) * 1.5
        + coalesce(s.skip_count, 0) * 1.0
      )::numeric as history_penalty,
      coalesce(h.completed_count, 0) as completed_count,
      coalesce(h.active_now, false) as active_now
    from public.quests q
    left join history h on h.quest_id = q.id
    left join skips s on s.quest_id = q.id
    where q.is_active = true
      and not (q.id = any(coalesce(p_excluded_quest_ids, '{}'::text[])))
  )
  select
    f.quest_id,
    (
      case when f.time_match then 4 else 0 end
      + case when f.interest_match then 3 else 0 end
      + case when f.social_match then 2 else 0 end
      + case when f.location_match then 1 else 0 end
      - f.history_penalty
    )::numeric as score,
    f.time_match,
    f.interest_match,
    f.social_match,
    f.location_match,
    f.history_penalty
  from features f
  where f.time_match = true
    and f.completed_count = 0
    and f.active_now = false
  order by score desc, f.quest_id
  limit least(greatest(coalesce(p_limit, 3), 1), 10);
$$;

revoke all on function public.recommend_quests(integer, text, text[], text, text[], integer)
from public, anon;

grant execute on function public.recommend_quests(integer, text, text[], text, text[], integer)
to authenticated;
