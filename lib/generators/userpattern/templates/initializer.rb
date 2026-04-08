# frozen_string_literal: true

UserPattern.configure do |config|
  # ─── Tracked models ────────────────────────────────────────────────
  # Each entry needs a :name and optionally a :current_method.
  # If :current_method is omitted, it defaults to :current_<underscored_name>.
  config.tracked_models = [
    { name: "User", current_method: :current_user },
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
  # Protect the dashboard. The Proc runs in the controller context.
  #
  # Example with HTTP Basic Auth:
  #   config.dashboard_auth = -> {
  #     authenticate_or_request_with_http_basic("UserPattern") do |user, pass|
  #       ActiveSupport::SecurityUtils.secure_compare(user, "admin") &
  #         ActiveSupport::SecurityUtils.secure_compare(pass, ENV["USERPATTERN_PASSWORD"])
  #     end
  #   }
  #
  # Example with Devise:
  #   config.dashboard_auth = -> {
  #     redirect_to main_app.root_path unless current_user&.admin?
  #   }
  #
  config.dashboard_auth = nil

  # ─── Enable / disable ─────────────────────────────────────────────
  # config.enabled = true
end
