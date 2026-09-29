# Security Model

- Row Level Security is enabled on all exposed application tables.
- The anonymous role has no table access to application data.
- Authenticated users are restricted to their own profile, preferences, quest state and analytics records.
- The quest catalogue is read-only from mobile clients.
- The `handle_new_user` SECURITY DEFINER function cannot be called directly by public, anon or authenticated roles.
- Never expose a Supabase secret/service-role key in Kotlin or Flutter.
- Quest photos live in a private Storage bucket. Storage policies restrict upload,
  read and cleanup to an authenticated user's own quest-attempt folder. Database
  policies restrict proof records to that user's own attempt and photo-required step.
- Deleting a proof record is not allowed to mobile clients. Deleting an attempt
  cascades its proof records, but Storage objects need separate administrative
  cleanup; a database cascade does not remove files from Storage.
