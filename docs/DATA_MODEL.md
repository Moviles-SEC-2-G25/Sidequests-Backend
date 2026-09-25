# Data Model

## Core tables

- `profiles`: one application profile per Supabase Auth user.
- `user_preferences`: interests, difficulty, time, budget, social and location preferences.
- `quests`: shared Sidequest catalogue used by Kotlin and Flutter.
- `quest_steps`: ordered steps for each quest.
- `user_quests`: per-user quest state, progress and completion/abandonment data.
- `analytics_events`: append-only event stream used by the analytics engine and Business Questions.

## Ownership

Kotlin and Flutter share the same schema. Neither platform owns a private copy of backend data.

## Recommendation RPC output

`public.recommend_quests(p_available_minutes, p_social_level, p_interests, p_location_mode, p_excluded_quest_ids, p_limit, p_variant)` (migration 008) returns:

`quest_id text, score numeric, time_match boolean, interest_match boolean, social_match boolean, location_match boolean, history_penalty numeric, category text, variant text, rank_position integer`.

- `category` is `quests.category`, returned so clients can log and display it.
- `variant` is `control` or `diverse`, stable per user (BQ8 A/B experiment).
- `rank_position` is the 1-based position in the returned list.
- `variant` and `rank_position` are not stored in a new table or column; clients write them into `analytics_events.metadata` of `recommendation_shown` events. The `analytics_events` schema and RLS policies are unchanged.
