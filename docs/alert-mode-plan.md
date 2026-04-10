# Alert Mode — Data-Driven Rate Limiting Plan

## Overview

Add an alert mode to UserPattern that uses the max frequencies observed during collection as dynamic thresholds to block requests that exceed baseline usage patterns.

## UserPattern vs Rack::Attack

**In short:** Rack::Attack protects against known abuse patterns with manual rules. UserPattern learns what "normal authenticated usage" looks like and detects deviations automatically. They are complementary — Rack::Attack handles IP-level and unauthenticated abuse, UserPattern handles authenticated anomaly detection.

### What Rack::Attack does

Rack::Attack is Rack middleware for blocking and throttling abusive requests. It provides safelists, blocklists, throttles, and tracks. It operates at the Rack level (before Rails), identifies clients primarily by IP or request properties, and uses **static, developer-defined thresholds** (`limit: 5, period: 60`). State is stored in a cache backend (`Rails.cache`, Redis, Memcached) via the `ActiveSupport::Cache::Store` interface.

### Where UserPattern fills a gap

| Aspect | Rack::Attack | UserPattern |
|---|---|---|
| **Thresholds** | Static, manually configured | Dynamic, learned from observed usage data |
| **Target** | Any client (usually IP-based) | Authenticated users by model type (User, Admin) |
| **Awareness** | Rack-level, no access to `current_user` | Controller-level, resolves authenticated identity |
| **Analytics** | None (logging via ActiveSupport::Notifications) | Dashboard with per-endpoint, per-model-type stats |
| **Baseline** | Developer defines "normal" | System observes "normal" during collection |
| **URL handling** | Raw URLs | Auto-normalized (IDs, UUIDs, query params) |
| **Privacy** | N/A | Anonymized collection, no PII in DB |

### Reusing Rack::Attack's cache approach

Instead of a custom `Concurrent::Map` (per-process only), we should use `ActiveSupport::Cache::Store` — the same interface Rack::Attack uses. This gives us:

- **Multi-process support out of the box** — Redis/Memcached backends are shared across Puma workers
- **No custom purge logic needed** — cache entries expire naturally via `expires_in:`
- **Battle-tested** — same approach powering Rack::Attack in production at scale
- **Configurable** — defaults to `Rails.cache`, can be pointed at a dedicated store

```ruby
# Counter operations use the same API as Rack::Attack:
cache.increment("userpattern:42:GET /api/users:minute:2026-04-08T14:35", 1, expires_in: 2.minutes)
cache.read("userpattern:42:GET /api/users:minute:2026-04-08T14:35")  # => 7
```

The `expires_in` values provide natural cleanup:
- Minute counters: `expires_in: 2.minutes`
- Hour counters: `expires_in: 2.hours`
- Day counters: `expires_in: 2.days`

## Core Concept

The thresholds are **not configured statically** — they are derived from the `max_per_minute`, `max_per_hour`, `max_per_day` already computed by `StatsCalculator` during collection. A configurable multiplier (default 1.5x) provides tolerance.

Flow:

1. Run in **collection mode** for days/weeks — observe that `GET /api/users` has max 5/min, 30/h, 100/day
2. Switch to **alert mode** — those observed maximums (x multiplier) become the thresholds
3. If a user exceeds those thresholds — the configured response actions are triggered

## Two Sides of the Comparison

### Left side — "What is this user doing right now?" (Cache counters)

On every request, increment a counter for the current user on the current endpoint in three time buckets (minute, hour, day) using `ActiveSupport::Cache::Store#increment`.

```
Key format: "userpattern:#{user_id}:#{endpoint}:#{period}:#{bucket}"

"userpattern:42:GET /api/users:minute:2026-04-08T14:35"   → expires_in: 2.minutes
"userpattern:42:GET /api/users:hour:2026-04-08T14"        → expires_in: 2.hours
"userpattern:42:GET /api/users:day:2026-04-08"            → expires_in: 2.days
```

### Right side — "What is normal?" (ThresholdCache, RAM)

A `Hash` rebuilt every `threshold_refresh_interval` seconds (default 5 min) from `StatsCalculator.compute_all`:

```ruby
@limits = {
  ["User", "GET /api/sinistres/:id"] => { per_minute: 8, per_hour: 45, per_day: 150 },
  ["User", "GET /api/users"]         => { per_minute: 15, per_hour: 90, per_day: 300 },
  ["Admin", "POST /api/export"]      => { per_minute: 3, per_hour: 10, per_day: 20 },
}
```

Each value is computed as:

```ruby
# stat[:max_per_minute] = 5   (observed max during collection)
# threshold_multiplier  = 1.5 (configured)
# => (5 * 1.5).ceil = 8
```

`ceil` ensures we never set a limit below the observed max.

## Request Flow in Alert Mode

```
before_action (alert mode only)
    ├─ Resolve current_user → user_id=42, model_type="User"
    ├─ Normalize endpoint → "GET /api/sinistres/:id"
    ├─ RateLimiter.check_and_increment!(42, "User", "GET /api/sinistres/:id")
    │   ├─ Increment minute/hour/day counters via cache store
    │   ├─ Fetch limits from ThresholdCache for ("User", "GET /api/sinistres/:id")
    │   ├─ Compare: minute_count <= per_minute? hour_count <= per_hour? day_count <= per_day?
    │   ├─ All OK → continue
    │   └─ Any exceeded → trigger response actions
    │
after_action (always active — collection continues in alert mode)
    └─ Buffer anonymized event as usual
```

## Response Actions (beyond raising an exception)

Raising `ThresholdExceeded` alone is not sufficient. The system should support configurable response actions when a threshold is exceeded.

### Built-in actions

| Action | Description |
|---|---|
| `:raise` | Raise `ThresholdExceeded` (default). Host app handles via `rescue_from`. |
| `:logout` | Call a configurable logout method (e.g. `sign_out(current_user)` for Devise) to terminate the session. |
| `:log` | Record the violation to `Rails.logger` and/or `ActiveSupport::Notifications`. |
| `:record` | Persist the violation to a `userpattern_violations` table for dashboard display. |

### Configuration

```ruby
UserPattern.configure do |config|
  config.mode = :alert

  # Which actions to take when a threshold is exceeded (can combine multiple)
  config.violation_actions = [:record, :log, :raise]

  # Logout configuration (only used if :logout is in violation_actions)
  config.logout_method = ->(controller) { controller.sign_out(controller.current_user) }

  # Optional callback for custom handling (Sentry, Slack, etc.)
  config.on_threshold_exceeded = ->(violation) {
    Sentry.capture_message("Rate limit: #{violation.message}")
  }
end
```

### Violation recording

When `:record` is in `violation_actions`, violations are persisted to a `userpattern_violations` table:

```ruby
# Schema
create_table :userpattern_violations do |t|
  t.string   :model_type,  null: false      # "User"
  t.string   :endpoint,    null: false      # "GET /api/sinistres/:id"
  t.string   :period,      null: false      # "minute"
  t.integer  :count,       null: false      # 9
  t.integer  :limit,       null: false      # 8
  t.string   :user_identifier, null: false  # hashed, NOT the raw user ID
  t.datetime :occurred_at, null: false
  t.datetime :created_at,  null: false
end
```

**Privacy note:** The `user_identifier` column stores a one-way hash of the user ID (same HMAC approach as `anonymous_session_id`), NOT the raw ID. This allows counting distinct offenders and showing frequency without exposing identities. The raw user ID only appears in the exception/logs — never in the DB.

### Dashboard integration

The dashboard gets a new "Violations" tab showing:

| Column | Description |
|---|---|
| Endpoint | The offending endpoint |
| Model Type | User, Admin, etc. |
| Period | minute, hour, or day |
| Count / Limit | e.g. "9 / 8" |
| Distinct Offenders | Count of distinct hashed user identifiers |
| Last Occurred | Timestamp of most recent violation |

## The Exception

```ruby
class UserPattern::ThresholdExceeded < StandardError
  attr_reader :endpoint, :user_id, :model_type, :period, :count, :limit

  # message: "Rate limit exceeded: GET /api/users — 9/minute (max: 8) by User#42"
end
```

The host app handles it:

```ruby
class ApplicationController < ActionController::Base
  rescue_from UserPattern::ThresholdExceeded do |e|
    render json: { error: "Too many requests" }, status: :too_many_requests
  end
end
```

## Dashboard Authentication — Secure by Default

The current plan has `dashboard_auth = nil` (unprotected by default). This is a vulnerability.

**New default:** require HTTP Basic Auth with credentials from environment variables:

```ruby
# Default behavior when dashboard_auth is not explicitly configured:
# Requires USERPATTERN_DASHBOARD_USER and USERPATTERN_DASHBOARD_PASSWORD env vars.
# If neither is set, the dashboard returns 403 with a setup instructions page.
```

This means:
- **Out of the box:** dashboard is locked (403) until env vars are set or custom auth is configured
- **Minimal setup:** set 2 env vars and it works
- **Full control:** override with a custom Proc as before (Devise, IP allowlist, etc.)

```ruby
# In configuration.rb
def dashboard_auth
  @dashboard_auth || default_dashboard_auth
end

private

def default_dashboard_auth
  user = ENV["USERPATTERN_DASHBOARD_USER"]
  pass = ENV["USERPATTERN_DASHBOARD_PASSWORD"]
  return -> { head :forbidden } unless user && pass

  lambda {
    authenticate_or_request_with_http_basic("UserPattern") do |u, p|
      ActiveSupport::SecurityUtils.secure_compare(u, user) &
        ActiveSupport::SecurityUtils.secure_compare(p, pass)
    end
  }
end
```

## Full Configuration

```ruby
UserPattern.configure do |config|
  config.mode = :collection              # :collection or :alert

  config.threshold_multiplier = 1.5      # limit = observed_max * multiplier
  config.threshold_refresh_interval = 300 # reload limits from DB every N seconds
  config.block_unknown_endpoints = false  # allow endpoints never seen in collection

  # Cache store for rate limiter counters (defaults to Rails.cache)
  config.rate_limiter_store = Rails.cache
  # Or use a dedicated store:
  # config.rate_limiter_store = ActiveSupport::Cache::RedisCacheStore.new(url: "redis://localhost:6379/1")

  # Actions to take when threshold exceeded (combine multiple)
  config.violation_actions = [:record, :log, :raise]

  # Logout configuration (for :logout action)
  config.logout_method = ->(controller) { controller.sign_out(controller.current_user) }

  # Optional callback
  config.on_threshold_exceeded = ->(violation) {
    Sentry.capture_message("Rate limit: #{violation.message}")
  }
end
```

## Edge Cases

### Unknown endpoints

If `POST /api/new_feature` was never seen during collection, the ThresholdCache has no entry. With `block_unknown_endpoints: false` (default), it passes through. With `true`, it gets blocked.

### Empty collection data

If no data has been collected yet and mode is switched to `:alert`, all endpoints are unknown — everything passes through (unless `block_unknown_endpoints: true`).

### Multiplier edge case

Observed max of 1/min with multiplier 1.5 → `(1 * 1.5).ceil = 2`. The user can make 2 requests/minute before being blocked. Multiplier of 1.0 → strict enforcement of the observed max.

## Performance

| Operation | Cost |
|---|---|
| 3x cache `increment` (minute/hour/day) | ~0.1ms in-process, ~0.5ms with Redis |
| 3x cache `read` for current counts | included in increment return value |
| 1x `Hash` lookup in ThresholdCache (RAM) | ~0.1 microseconds |
| 3x integer comparisons | ~negligible |
| **Total per request (in-process cache)** | **< 0.5ms** |
| **Total per request (Redis)** | **< 2ms** |

## Privacy

```
DB: userpattern_request_events  → anonymous_session_id (HMAC, no user ID)
DB: userpattern_violations      → user_identifier (HMAC hash, not raw ID)
Cache (ephemeral)               → user.id in counter keys (expires automatically)
ThresholdExceeded exception     → user.id in message (handled by host app)
Rails.logger                    → user.id if :log action is enabled
```

Raw user IDs never reach the database. They exist only in ephemeral cache keys, exceptions, and logs — all controlled by the host app.

## Files to Create

- `lib/userpattern/threshold_exceeded.rb` — exception class (already created)
- `lib/userpattern/threshold_cache.rb` — periodic DB loader, builds limits hash
- `lib/userpattern/rate_limiter.rb` — cache-backed counters, check_and_increment!
- `lib/userpattern/violation_recorder.rb` — persists anonymized violations to DB
- `app/models/user_pattern/violation.rb` — ActiveRecord model for violations
- Migration template for `userpattern_violations` table

## Files to Modify

- `lib/userpattern/configuration.rb` — new config attributes (already partially updated)
- `lib/userpattern/controller_tracking.rb` — add `before_action` for alert mode
- `lib/userpattern/engine.rb` — initialize cache/limiter when mode is :alert
- `lib/userpattern.rb` — add `rate_limiter` and `threshold_cache` accessors
- `app/controllers/user_pattern/dashboard_controller.rb` — violations tab, secure by default
- `app/views/user_pattern/dashboard/index.html.erb` — violations tab, threshold column
- `config/routes.rb` — violations route if needed
- `lib/generators/userpattern/install_generator.rb` — add violations migration
- `README.md` — document alert mode, Rack::Attack comparison, secure dashboard

## Tests to Add

- `threshold_cache_spec.rb` — loads from stats, applies multiplier, handles missing endpoints
- `rate_limiter_spec.rb` — increment, threshold check, cache expiry, unknown endpoint handling
- `threshold_exceeded_spec.rb` — message format, attributes
- `violation_recorder_spec.rb` — persists with hashed user ID, never raw ID
- `controller_tracking_spec.rb` — alert mode: blocks over-limit, allows under-limit, triggers actions
- `dashboard_spec.rb` — secure by default (403 without env vars), violations tab
