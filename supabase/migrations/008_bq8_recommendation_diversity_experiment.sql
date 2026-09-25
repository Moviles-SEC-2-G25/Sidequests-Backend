-- BQ8: recommendation diversity experiment (Type 3).
-- Extends the shared BQ5 RPC with a server-side A/B variant so Kotlin and Flutter
-- do not implement (or assign) the experiment themselves.
--
--   control : BQ5 ranking unchanged (score desc).
--   diverse : same score, minus a novelty penalty for quests this user was shown
--             in the last 7 days and a penalty for repeating a category inside
--             the returned list.
--
-- Variant is stable per user (hash of auth.uid()), so each user always sees the
-- same arm. p_variant lets tests/demos force an arm.
-- The RPC returns `variant` and `rank_position`; clients copy them into the
-- metadata of `recommendation_shown` events (see Sidequests-Analytics
-- docs/EVENT_SCHEMA.md) so analytics can compare arms.

drop function if exists public.recommend_quests(integer, text, text[], text, text[], integer);

create or replace function public.recommend_quests(
  p_available_minutes integer,
  p_social_level text,
  p_interests text[] default '{}'::text[],
  p_location_mode text default 'all',
  p_excluded_quest_ids text[] default '{}'::text[],
  p_limit integer default 3,
  p_variant text default null
)
returns table (
  quest_id text,
  score numeric,
  time_match boolean,
  interest_match boolean,
  social_match boolean,
  location_match boolean,
  history_penalty numeric,
  category text,
  variant text,
  rank_position integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  with params as (
    select
      case
        when lower(coalesce(p_variant, '')) in ('control', 'diverse')
          then lower(p_variant)
        when mod(hashtext(auth.uid()::text), 2) = 0 then 'control'
        else 'diverse'
      end as variant,
      least(greatest(coalesce(p_limit, 3), 1), 10) as lim
  ),
  history as (
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
  recent_shown as (
    select
      ae.quest_id,
      count(*) as shown_count
    from public.analytics_events ae
    where ae.user_id = auth.uid()
      and ae.event_type = 'recommendation_shown'
      and ae.quest_id is not null
      and ae.occurred_at >= now() - interval '7 days'
    group by ae.quest_id
  ),
  features as (
    select
      q.id as quest_id,
      q.category,
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
      coalesce(rs.shown_count, 0) as recent_shown_count,
      coalesce(h.completed_count, 0) as completed_count,
      coalesce(h.active_now, false) as active_now
    from public.quests q
    left join history h on h.quest_id = q.id
    left join skips s on s.quest_id = q.id
    left join recent_shown rs on rs.quest_id = q.id
    where q.is_active = true
      and not (q.id = any(coalesce(p_excluded_quest_ids, '{}'::text[])))
  ),
  base as (
    select
      f.*,
      (
        case when f.time_match then 4 else 0 end
        + case when f.interest_match then 3 else 0 end
        + case when f.social_match then 2 else 0 end
        + case when f.location_match then 1 else 0 end
        - f.history_penalty
      )::numeric as base_score
    from features f
    where f.time_match = true
      and f.completed_count = 0
      and f.active_now = false
  ),
  novelty as (
    select
      b.*,
      -- diverse arm: demote quests already shown to this user this week
      (b.base_score - 0.5 * least(b.recent_shown_count, 4))::numeric as novelty_score
    from base b
  ),
  diversified as (
    select
      n.*,
      row_number() over (
        partition by n.category
        order by n.novelty_score desc, n.quest_id
      ) as category_rank
    from novelty n
  ),
  final_scored as (
    select
      d.*,
      p.variant,
      p.lim,
      case
        when p.variant = 'diverse'
          -- diverse arm: each further quest of an already-present category loses 1.5
          then (d.novelty_score - 1.5 * (d.category_rank - 1))::numeric
        else d.base_score
      end as final_score
    from diversified d
    cross join params p
  ),
  ranked as (
    select
      fs.*,
      row_number() over (order by fs.final_score desc, fs.quest_id)::integer as rank_position
    from final_scored fs
  )
  select
    r.quest_id,
    r.final_score as score,
    r.time_match,
    r.interest_match,
    r.social_match,
    r.location_match,
    r.history_penalty,
    r.category,
    r.variant,
    r.rank_position
  from ranked r
  where r.rank_position <= r.lim
  order by r.rank_position;
$$;

revoke all on function public.recommend_quests(integer, text, text[], text, text[], integer, text)
from public, anon;

grant execute on function public.recommend_quests(integer, text, text[], text, text[], integer, text)
to authenticated;
