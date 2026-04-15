# frozen_string_literal: true

UserPattern.configure do |config|
  # ─── Tracked models ────────────────────────────────────────────────
  # Each entry needs a :name and optionally a :current_method.
  # If :current_method is omitted, it defaults to :current_<underscored_name>.
  config.tracked_models = [
    { name: 'User', current_method: :current_user }
    # { name: "Admin", current_method: :current_admin },
  ]

  # ─── Session detection ─────────────────────────────────────────────
  # How to identify a session for anonymized grouping.
  #   :auto    – use Authorization header (JWT) if present, otherwise session cookie
  #   :session – always use session cookie
  #   :header  – always use Authorization header
  #   Proc     – custom: ->(request) { request.headers["X-Session-Token"] }
  config.session_detection = :auto

  # ─── Performance ───────────────────────────────────────────────────
  # Events are buffered in memory and flushed in batches.
  # config.buffer_size    = 100   # flush when buffer reaches this size
  # config.flush_interval = 30    # flush at least every N seconds

  # ─── Data retention ────────────────────────────────────────────────
  # Raw events older than this are deleted by `rake userpattern:cleanup`.
  # config.retention_period = 30  # days

  # ─── Dashboard authentication ──────────────────────────────────────
  # The dashboard is secure by default. Set these environment variables:
  #   USERPATTERN_DASHBOARD_USER
  #   USERPATTERN_DASHBOARD_PASSWORD
  #
  # Or provide a custom Proc:
  #   config.dashboard_auth = -> {
  #     redirect_to main_app.root_path unless current_user&.admin?
  #   }

  # ─── Mode ──────────────────────────────────────────────────────────
  # :collection — observe and record usage patterns (default)
  # :alert      — enforce rate limits derived from observed data
  # config.mode = :collection

  # ─── Alert mode settings ───────────────────────────────────────────
  # config.threshold_multiplier = 1.5       # limit = observed_max * multiplier
  # config.threshold_refresh_interval = 300 # reload limits from DB every N seconds
  # config.block_unknown_endpoints = false  # allow endpoints not seen during collection

  # Cache store for rate-limiter counters (defaults to Rails.cache).
  # For multi-process setups, use Redis:
  # config.rate_limiter_store = ActiveSupport::Cache::RedisCacheStore.new(url: ENV["REDIS_URL"])

  # Actions to take when a threshold is exceeded (combine multiple):
  #   :raise   — raise ThresholdExceeded (handle via rescue_from)
  #   :log     — write to Rails.logger
  #   :record  — persist to userpattern_violations table (visible in dashboard)
  #   :logout  — call config.logout_method to terminate the session
  # config.violation_actions = [:raise]

  # Logout method (only used when :logout is in violation_actions):
  # config.logout_method = ->(controller) { controller.sign_out(controller.current_user) }

  # Optional callback for custom handling (Sentry, Slack, etc.):
  # config.on_threshold_exceeded = ->(violation) {
  #   Sentry.capture_message("Rate limit: #{violation.message}")
  # }

  # ─── Ignored paths ────────────────────────────────────────────────
  # Paths matching any entry are silently skipped — no event is recorded.
  # Each entry can be a String (exact match) or a Regexp (pattern match).
  # Matching is performed against the raw request path (no query string).
  #
  # Examples:
  #   config.ignored_paths = [
  #     "/health",            # exact match
  #     "/up",
  #     %r{\A/api/internal},  # any path starting with /api/internal
  #   ]
  # config.ignored_paths = []

  # ─── Enable / disable ─────────────────────────────────────────────
  # config.enabled = true
end
