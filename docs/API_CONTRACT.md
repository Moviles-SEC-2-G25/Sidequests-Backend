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

## Shared rule
Changes to database structure or shared server-side behavior must be versioned in this repository before both clients depend on them.
