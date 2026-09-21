# Security Model

- Row Level Security is enabled on all exposed application tables.
- The anonymous role has no table access to application data.
- Authenticated users are restricted to their own profile, preferences, quest state and analytics records.
- The quest catalogue is read-only from mobile clients.
- The `handle_new_user` SECURITY DEFINER function cannot be called directly by public, anon or authenticated roles.
- Never expose a Supabase secret/service-role key in Kotlin or Flutter.
