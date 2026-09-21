# Sidequests Backend

Shared backend for the Sidequests Kotlin and Flutter applications.

## Stack

- Supabase Auth
- PostgreSQL
- Row Level Security (RLS)
- Supabase Storage (when needed)
- Supabase Edge Functions for shared server-side integrations

Both mobile clients use the same Supabase project and the same data model.

## Repository structure

```text
supabase/
├── migrations/
│   ├── 001_foundation_schema_rls.sql
│   ├── 002_security_and_index_hardening.sql
│   └── 003_make_quest_coordinates_optional.sql
├── seed.sql
└── functions/
    └── context-weather/
docs/
├── DATA_MODEL.md
├── API_CONTRACT.md
└── SECURITY.md
```

## Current validated state

- Supabase project created in São Paulo.
- Email/password authentication validated from the Kotlin app.
- Automatic profile and preference creation validated.
- 8 quests and 32 quest steps seeded.
- Kotlin app validated reading the remote catalogue.
- RLS enabled on all exposed application tables.
- Supabase Security Advisor currently reports no security warnings.

## Important

Do not commit service-role or secret keys. Mobile clients must use only the Supabase publishable key.
