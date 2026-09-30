# Photo proof deployment and handoff

Review and merge the `feature/quest-photo-proofs` PR, then apply the complete
`supabase/migrations/009_quest_photo_proofs.sql` to the shared Supabase project.
The deployed project URL is supplied through the clients' existing configuration;
the GitHub repository only versions the backend. A publishable key cannot deploy
SQL migrations or create the bucket administratively.

The migration creates the private JPEG bucket and the proof table together. Kotlin
requires both: a Storage upload alone is not considered a registered proof. Existing
Auth, quest progress, BQ5 and analytics structures do not change.

## Local policy tests

Run `npm ci` and `npm test` (Node.js 22). The test runs all repository migrations and
the catalogue seed in in-memory PostgreSQL using PGlite. Minimal Supabase Auth and
Storage schema fixtures provide roles, `auth.uid()` and `storage.foldername()`.

Tests cover owner upload/read/cleanup, per-step registration, cross-user rejection,
anonymous rejection, missing objects, wrong steps/quests and malformed paths.
These exercise SQL and RLS; they do not simulate Storage HTTP behavior, MIME checks,
file-size enforcement or the Android camera.

## Teammates' runtime check

1. Confirm the complete migration has been applied to the shared project. Inspect
   the bucket's private setting and the three `quest_proofs_*` Storage policies.
   Review any older policies on `storage.objects`: permissive policies combine with
   OR, so a pre-existing broad policy could bypass ownership checks.
2. Run the updated Lex Kotlin branch with its existing Supabase URL/publishable key
   and bucket setting `quest-proofs`. Authenticate, accept a quest, and reach a step
   whose `verification_type` is `photo` or `photo_and_location`.
3. Capture a photo or use **Retry upload** on a locally captured one. The expected
   label is **Photo proof captured and uploaded**.
4. Confirm the Storage object path starts with the user's ID and attempt ID, and a
   `quest_photo_proofs` row has that path, the attempt, and the zero-based step order.
   Confirm a `photo_proof_uploaded` analytics event was saved for the same attempt.
5. With a second authenticated account, confirm the first account's evidence cannot
   be listed, downloaded or deleted. Anonymous access must also fail.
6. Temporarily disconnect the device before a capture: the local proof remains and
   **Retry upload** succeeds when the connection returns.

Uploads use new paths (`upsert = false`). INSERT, SELECT and DELETE are allowed for
an owner's attempt; UPDATE is intentionally unavailable. Proof table rows are
append-only to clients. If registering the row fails, Kotlin attempts to delete the
new upload; if cleanup also fails, an administrator may need to remove the orphan.
