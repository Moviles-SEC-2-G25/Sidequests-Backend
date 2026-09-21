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
