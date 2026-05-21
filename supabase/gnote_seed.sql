BEGIN;

-- =========================================================
-- gnote.app_settings
-- Global application settings used by workflows
-- =========================================================

INSERT INTO gnote.app_settings (
  key,
  value,
  description,
  updated_at
)
VALUES
  (
    'search.max_results_limit',
    '100'::jsonb,
    'Maximum number of search results stored per search session',
    NOW()
  ),
  (
    'search.default_top_limit',
    '10'::jsonb,
    'Default number of top search results shown to the user',
    NOW()
  ),
  (
    'pending.cleanup_hours',
    '24'::jsonb,
    'Pending messages and pending AI metadata older than this number of hours may be removed by cleanup workflow',
    NOW()
  ),
  (
    'files.max_supported_size_mb',
    '1'::jsonb,
    'Maximum supported file size in MB for AI analysis',
    NOW()
  ),
  (
    'media.video_supported',
    'false'::jsonb,
    'Whether video files are supported for AI analysis',
    NOW()
  ),
  (
    'media.video_note_supported',
    'false'::jsonb,
    'Whether Telegram video notes are supported for AI analysis',
    NOW()
  ),
  (
    'media.large_files_supported',
    'false'::jsonb,
    'Whether files larger than the configured limit are supported',
    NOW()
  )
ON CONFLICT (key)
DO UPDATE SET
  value = EXCLUDED.value,
  description = EXCLUDED.description,
  updated_at = NOW();


-- =========================================================
-- gnote.message_rate_limit_settings
-- Single-row global rate limit config
-- =========================================================

INSERT INTO gnote.message_rate_limit_settings (
  id,
  enabled,
  max_messages,
  window_minutes,
  updated_at
)
VALUES (
  1,
  TRUE,
  10,
  60,
  NOW()
)
ON CONFLICT (id)
DO UPDATE SET
  enabled = EXCLUDED.enabled,
  max_messages = EXCLUDED.max_messages,
  window_minutes = EXCLUDED.window_minutes,
  updated_at = NOW();

COMMIT;