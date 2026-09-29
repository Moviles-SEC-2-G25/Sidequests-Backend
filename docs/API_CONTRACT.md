# Shared Mobile Contract

Both Kotlin and Flutter use the same Supabase project.

## Authentication
- Email/password through Supabase Auth.
- Mobile clients use the publishable key only.

## Read operations
- Active quests and quest steps are readable by authenticated users.
- A user can read only their own profile, preferences, quest progress and analytics events.

## Write operations
- A user can update only their own profile/preferences.
- A user can create/update only their own `user_quests`.
- Analytics events are append-only from mobile clients.
- Mobile clients cannot edit the quest catalogue directly.
- Authenticated users can insert and read proof records only for their own attempts
  and photo-required steps. Proof records cannot be changed or deleted by a client.

## Shared rule
Changes to database structure or shared server-side behavior must be versioned in this repository before both clients depend on them.

## Quest photo proof

Migration `009_quest_photo_proofs.sql` creates the private `quest-proofs` Storage bucket
and `public.quest_photo_proofs`. An authenticated client uploads a JPEG to:

```text
<user-id>/<attempt-id>/<quest-id>/step-<1-based-step-number>-<uuid>.jpg
```

After upload, insert into `quest_photo_proofs` with `attempt_id`, zero-based
`step_order`, and `storage_path`. Only report success after that insert succeeds.
If it fails, delete the newly uploaded object and allow a retry. Read the table
by `attempt_id` to find evidence; use an authenticated Storage download or signed
URL, never a public URL. The bucket accepts JPEGs up to 25 MiB. The server checks
that the attempt belongs to the user and the step requires a photo.

The optional `SUPABASE_QUEST_PROOFS_BUCKET` client setting must remain
`quest-proofs` unless a matching bucket and policies are deployed.

## Recommendations (BQ5 / BQ8)

Shared RPC `public.recommend_quests`, called through PostgREST (`POST /rest/v1/rpc/recommend_quests`) by an authenticated user. `anon` and `public` cannot execute it.

Parameters (send by name; all but the first two have defaults, so existing calls without `p_variant` keep working):

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `p_available_minutes` | integer | – | Quests longer than this are excluded. |
| `p_social_level` | text | – | Empty/null matches any. |
| `p_interests` | text[] | `{}` | Matched against category and tags. |
| `p_location_mode` | text | `'all'` | |
| `p_excluded_quest_ids` | text[] | `{}` | Quests rejected in the current session. |
| `p_limit` | integer | `3` | Clamped to 1–10. |
| `p_variant` | text | `null` | `'control'` or `'diverse'` forces an arm (tests/demos). Otherwise the server assigns one. |

Returned columns: `quest_id`, `score`, `time_match`, `interest_match`, `social_match`, `location_match`, `history_penalty`, `category`, `variant`, `rank_position` (1-based).

### BQ8 diversity experiment
- The arm is assigned server-side and is stable per user (hash of `auth.uid()`); clients must not assign or override it in production.
- `control`: BQ5 ranking unchanged (score descending).
- `diverse`: same score, minus 0.5 per showing (max 4) in the last 7 days from `recommendation_shown` events, and minus 1.5 for each additional quest of a category already ranked higher in the same result.
- Clients must copy `variant` and `rank_position` into the metadata of `recommendation_shown` events (see Sidequests-Analytics `docs/EVENT_SCHEMA.md`). The `analytics_events` schema is unchanged.

Migration: `supabase/migrations/008_bq8_recommendation_diversity_experiment.sql` (replaces the 6-argument signature from 007).
