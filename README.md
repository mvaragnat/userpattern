# UserPattern

Anonymized usage-pattern analysis for Rails applications.

UserPattern plugs into any Rails app as an engine. It intercepts requests from authenticated users, collects per-endpoint frequency statistics, and presents a sortable dashboard — all without ever storing a user identifier. In **alert mode**, it enforces rate limits derived from the observed data.

## Features

- **Multi-model** — track `User`, `Admin`, or any authenticatable model.
- **Devise + JWT compatible** — auto-detects session cookies and `Authorization` headers.
- **Fully anonymized** — impossible to trace actions back to a specific user (daily-rotating HMAC salt).
- **Minimal performance impact** — in-memory buffer, async batch writes.
- **Built-in dashboard** — sortable HTML table, filterable by model type, with violations tab.
- **Automatic cleanup** — rake task to purge expired data.
- **Two modes** — collection (observe) and alert (enforce rate limits from observed data).
- **Secure by default** — dashboard requires authentication out of the box.

## UserPattern vs Rack::Attack

Rack::Attack and UserPattern are **complementary**. Rack::Attack protects against known abuse patterns with manual rules. UserPattern learns what "normal authenticated usage" looks like and detects deviations automatically.

| Aspect | Rack::Attack | UserPattern |
|---|---|---|
| **Thresholds** | Static, manually configured | Dynamic, learned from observed usage data |
| **Target** | Any client (usually IP-based) | Authenticated users by model type (User, Admin) |
| **Awareness** | Rack-level, no access to `current_user` | Controller-level, resolves authenticated identity |
| **Analytics** | None (logging via ActiveSupport::Notifications) | Dashboard with per-endpoint, per-model-type stats |
| **Baseline** | Developer defines "normal" | System observes "normal" during collection |
| **URL handling** | Raw URLs | Auto-normalized (IDs, UUIDs, query params) |
| **Privacy** | N/A | Anonymized collection, no PII in DB |

**When to use Rack::Attack:** IP-level rate limiting, blocking known bad actors, unauthenticated abuse prevention, DDoS protection.

**When to use UserPattern:** Detecting authenticated users who deviate from normal behavior, understanding endpoint usage patterns, adaptive rate limiting without manual threshold tuning.

**Using both together:** Rack::Attack as the outer wall (IP-based, Rack middleware), UserPattern as the inner guard (identity-based, controller-level). UserPattern reuses the same `ActiveSupport::Cache::Store` interface as Rack::Attack for its rate limiter counters, so the two share a common cache infrastructure.

## Installation

Add to your application's `Gemfile`:

```ruby
gem "userpattern", path: "path/to/userpattern"   # local development
# gem "userpattern", github: "your-org/userpattern"  # via GitHub
```

Run the install generator:

```bash
bundle install
rails generate userpattern:install
rails db:migrate
```

The generator creates:
1. `config/initializers/userpattern.rb` — configuration file
2. Migrations for `userpattern_request_events` and `userpattern_violations` tables
3. A route mounting the dashboard at `/userpatterns`

## Configuration

```ruby
# config/initializers/userpattern.rb

UserPattern.configure do |config|
  # Models to track. Each entry needs :name and optionally :current_method.
  # If :current_method is omitted it defaults to :current_<underscored_name>.
  config.tracked_models = [
    { name: "User", current_method: :current_user },
    { name: "Admin", current_method: :current_admin },
  ]

  # Session detection mode (see "Session detection" section below)
  config.session_detection = :auto

  # Buffer tuning
  config.buffer_size    = 100  # flush when buffer reaches this size
  config.flush_interval = 30   # flush at least every N seconds

  # Data retention (days). Old events are removed by `rake userpattern:cleanup`.
  config.retention_period = 30

  # Enable / disable tracking globally
  config.enabled = true

  # ─── Alert mode ──────────────────────────────────────────────────
  config.mode = :collection              # :collection or :alert
  config.threshold_multiplier = 1.5      # limit = observed_max * multiplier
  config.threshold_refresh_interval = 300 # reload limits from DB every N seconds
  config.block_unknown_endpoints = false  # allow endpoints not seen during collection

  # Cache store for rate-limiter counters (defaults to Rails.cache)
  # config.rate_limiter_store = ActiveSupport::Cache::RedisCacheStore.new(url: ENV["REDIS_URL"])

  # Actions when a threshold is exceeded (:raise, :log, :record, :logout)
  config.violation_actions = [:record, :log, :raise]

  # Logout method (only used when :logout is in violation_actions)
  # config.logout_method = ->(controller) { controller.sign_out(controller.current_user) }

  # Optional callback for custom handling (Sentry, Slack, etc.)
  # config.on_threshold_exceeded = ->(violation) {
  #   Sentry.capture_message("Rate limit: #{violation.message}")
  # }
end
```

## Detecting the logged-in user

### Default strategy: `current_user`

UserPattern hooks into controllers via an `after_action` callback. For each configured model it calls the specified method (defaults to `current_user`):

```ruby
config.tracked_models = [
  { name: "User" },                                    # calls current_user
  { name: "Admin", current_method: :current_admin },   # calls current_admin
]
```

### Devise + classic sessions

With Devise, `current_user` is available in every controller through the Warden helper. **No extra configuration needed.**

### Devise + JWT (devise-jwt, devise-token-auth)

With `devise-jwt` or similar gems, Warden is configured to authenticate via the JWT token in the `Authorization` header. **`current_user` works out of the box for API requests too.**

The flow:
1. Client sends `Authorization: Bearer <token>`
2. Warden (via the JWT strategy) decodes the token and hydrates `current_user`
3. UserPattern calls `current_user` in the `after_action` — the user is detected

### Custom JWT (without Devise)

If you use a custom JWT system that does not populate `current_user`, either:

1. Define a `current_user` method in your `ApplicationController` that decodes the JWT, or
2. Point to your own method:

```ruby
config.tracked_models = [
  { name: "ApiClient", current_method: :current_api_client },
]
```

### Multiple models

When a request matches several models (e.g. a user who is both `User` and `Admin` through Devise scopes), all matching models are tracked independently.

## Anonymization

### How it works

UserPattern **never stores a user identifier** (no id, email, or any PII). It derives an opaque session fingerprint:

```
anonymous_session_id = HMAC-SHA256(
  key:   secret_key_base[0..31] + ":2026-04-08",
  value: session_id | authorization_header
)[0..15]
```

### Security properties

| Property | Guarantee |
|---|---|
| **Irreversible** | HMAC is one-way — cannot recover the session ID or user |
| **Daily rotation** | Salt changes every day — cross-day correlation is impossible |
| **Truncation** | Only 16 hex chars kept (64 bits), further reducing entropy |
| **No user↔action link** | No user ID in the database. Even with full DB access you can only see aggregate stats |

### URL and query string normalization

Endpoints are normalized **at collection time** so that URLs differing only by dynamic segments are aggregated into a single pattern. No raw URL ever reaches the database.

**Path segments** — numeric IDs, UUIDs, and long hex tokens are replaced with `:id`:

```
/sinistres/2604921/member_ratio    → /sinistres/:id/member_ratio
/sinistres/2605294/member_ratio    → /sinistres/:id/member_ratio   (same row)
/resources/84ef5373-0e95-4477-...  → /resources/:id
/verify/a1b2c3d4e5f6a7b8c9d0      → /verify/:id
```

**Query parameters** — values that look like IDs, UUIDs, or tokens are redacted with `:xxx`. Non-dynamic values (e.g. `status=active`) are preserved. Parameters are sorted so that different orderings map to the same endpoint:

```
/admin?application_id=84ef5373-...        → /admin?application_id=:xxx
/search?status=active                     → /search?status=active
/api?user_id=42&status=open&token=abc...  → /api?status=open&token=:xxx&user_id=:xxx
```

### Session detection modes

The default `:auto` mode picks the best source automatically:
- **`Authorization` header present** → hash the header (JWT / API case)
- **Session cookie present** → hash the session ID (browser case)
- **Neither** → hash the remote IP (fallback)

You can force a mode or provide a custom Proc:

```ruby
config.session_detection = :header   # always use the Authorization header
config.session_detection = :session  # always use the session cookie
config.session_detection = ->(request) { request.headers["X-Request-ID"] }
```

## Performance

UserPattern is designed to add negligible overhead to response times.

### Buffer architecture (collection)

```
HTTP request
    ↓
after_action (< 0.1ms)
    ↓ push
[Thread-safe in-memory buffer]   ← Concurrent::Array
    ↓ flush (async, every 30s or 100 events)
[Batch INSERT into DB]           ← ActiveRecord insert_all
```

- The `after_action` only pushes to a thread-safe array (~microseconds)
- Flushing happens in a separate thread — never blocks the request
- `insert_all` writes all buffered events in a single INSERT statement
- `buffer_size` and `flush_interval` are configurable

### Alert mode overhead

| Operation | Cost |
|---|---|
| 3x cache `increment` (minute/hour/day) | ~0.1ms in-process, ~0.5ms with Redis |
| 1x `Hash` lookup in ThresholdCache (RAM) | ~0.1 microseconds |
| 3x integer comparisons | ~negligible |
| **Total per request (in-process cache)** | **< 0.5ms** |
| **Total per request (Redis)** | **< 2ms** |

### Database indexes

Three indexes cover the dashboard queries:

- `(model_type, endpoint, recorded_at)` — time-bucketed aggregation
- `(model_type, endpoint, anonymous_session_id)` — distinct session counting
- `(recorded_at)` — expired event cleanup

### Cleanup

To prevent the table from growing indefinitely:

```bash
rails userpattern:cleanup
```

Schedule as a daily cron job. Deletes events older than `retention_period` (30 days by default).

## Dashboard

The dashboard is served at the engine mount path:

```ruby
# config/routes.rb
mount UserPattern::Engine, at: "/userpatterns"
```

### Usage tab

Displays per model type:

| Column | Description |
|---|---|
| **Endpoint** | HTTP method + path (e.g. `GET /api/users`) |
| **Total Reqs** | Total recorded requests |
| **Sessions** | Distinct anonymized sessions |
| **Avg / Session** | Average requests per session |
| **Avg / Min** | Average frequency per minute |
| **Max / Min** | Peak frequency over any 1-minute window |
| **Max / Hour** | Peak frequency over any 1-hour window |
| **Max / Day** | Peak frequency over any 1-day window |

In alert mode, three additional columns show the computed limits (max × multiplier).

All columns are sortable (click the header).

### Violations tab

When violations have been recorded (via `violation_actions: [:record, ...]`), the violations tab shows:

| Column | Description |
|---|---|
| **Endpoint** | The offending endpoint |
| **Model** | User, Admin, etc. |
| **Period** | minute, hour, or day |
| **Count** | Observed count that triggered the violation |
| **Limit** | The threshold that was exceeded |
| **User (hashed)** | Truncated HMAC hash (not the real user ID) |
| **Occurred At** | Timestamp |

## Securing the dashboard

The dashboard is **secure by default**. If no custom authentication is configured, it uses HTTP Basic Auth from environment variables.

### Default: environment variables

Set these two variables and the dashboard is protected:

```bash
export USERPATTERN_DASHBOARD_USER=admin
export USERPATTERN_DASHBOARD_PASSWORD=your-secret-password
```

If neither variable is set and no custom auth is configured, the dashboard returns **403 Forbidden** with setup instructions.

### Custom authentication

Override the default with a Proc that runs in the controller context:

#### HTTP Basic Auth (custom credentials)

```ruby
config.dashboard_auth = -> {
  authenticate_or_request_with_http_basic("UserPattern") do |user, pass|
    ActiveSupport::SecurityUtils.secure_compare(user, "admin") &
      ActiveSupport::SecurityUtils.secure_compare(pass, ENV["USERPATTERN_PASSWORD"])
  end
}
```

#### Devise (admin-only)

```ruby
config.dashboard_auth = -> {
  redirect_to main_app.root_path, alert: "Access denied" unless current_user&.admin?
}
```

#### Rails routing constraint

```ruby
# config/routes.rb
authenticate :user, ->(u) { u.admin? } do
  mount UserPattern::Engine, at: "/userpatterns"
end
```

#### IP allowlist

```ruby
config.dashboard_auth = -> {
  head :forbidden unless request.remote_ip.in?(%w[127.0.0.1 ::1])
}
```

## Alert mode

Alert mode turns UserPattern from a passive observer into an active rate limiter. Thresholds are **not configured manually** — they are derived from the max frequencies observed during collection.

### How it works

1. **Collection phase** — run in `:collection` mode for days or weeks. UserPattern observes that `GET /api/users` has a max of 5/min, 30/hour, 100/day.
2. **Switch to alert** — set `config.mode = :alert`. Those observed maximums (× `threshold_multiplier`) become the rate limits.
3. **Enforcement** — a `before_action` checks every request against the limits. If a user exceeds them, the configured response actions are triggered.

```
before_action (alert mode only)
    ├─ Resolve current_user → user_id=42, model_type="User"
    ├─ Normalize endpoint → "GET /api/sinistres/:id"
    ├─ RateLimiter.check_and_increment!(42, "User", "GET /api/sinistres/:id")
    │   ├─ Increment minute/hour/day counters via cache store
    │   ├─ Fetch limits from ThresholdCache
    │   ├─ Compare: count <= limit?
    │   ├─ All OK → continue
    │   └─ Any exceeded → trigger configured actions
    │
after_action (always active — collection continues in alert mode)
    └─ Buffer anonymized event as usual
```

### Enabling alert mode

```ruby
UserPattern.configure do |config|
  config.mode = :alert
  config.threshold_multiplier = 1.5       # limit = observed_max * 1.5
  config.threshold_refresh_interval = 300 # reload limits every 5 minutes
  config.violation_actions = [:record, :log, :raise]
end
```

### Threshold calculation

Limits are computed as `ceil(observed_max * threshold_multiplier)`:

```
Observed max_per_minute = 5, multiplier = 1.5 → limit = ceil(7.5) = 8
Observed max_per_hour   = 30                  → limit = ceil(45)  = 45
Observed max_per_day    = 100                 → limit = ceil(150) = 150
```

The ThresholdCache refreshes from the database every `threshold_refresh_interval` seconds (default: 300). As new data is collected, the thresholds evolve automatically.

### Violation actions

Configure which actions to take when a threshold is exceeded:

| Action | Description |
|---|---|
| `:raise` | Raise `ThresholdExceeded`. Handle via `rescue_from` in your controller. |
| `:log` | Log the violation to `Rails.logger` at warn level. |
| `:record` | Persist to `userpattern_violations` table. Visible in the dashboard. |
| `:logout` | Call `config.logout_method` to terminate the session. |

Actions can be combined:

```ruby
config.violation_actions = [:record, :log, :raise]
```

Without `:raise`, the request **continues normally** (useful for shadow/monitoring mode).

### ThresholdExceeded exception

When `:raise` is in `violation_actions`, a `UserPattern::ThresholdExceeded` error is raised. Handle it in your application controller:

```ruby
class ApplicationController < ActionController::Base
  rescue_from UserPattern::ThresholdExceeded do |e|
    render json: {
      error: "Too many requests",
      endpoint: e.endpoint,
      retry_after: 60
    }, status: :too_many_requests
  end
end
```

The exception exposes: `endpoint`, `user_id`, `model_type`, `period`, `count`, `limit`.

### Violation recording

When `:record` is in `violation_actions`, violations are persisted with an **anonymized user identifier** (HMAC hash, same approach as session anonymization). The raw user ID is never stored in the database.

### Cache store

Rate limiter counters use `ActiveSupport::Cache::Store` — the same interface as Rack::Attack. This gives multi-process support via Redis or Memcached:

```ruby
# Defaults to Rails.cache. For multi-process setups:
config.rate_limiter_store = ActiveSupport::Cache::RedisCacheStore.new(
  url: ENV["REDIS_URL"]
)
```

Counters expire automatically (`2.minutes`, `2.hours`, `2.days`) — no cleanup needed.

### Edge cases

**Unknown endpoints** — if `POST /api/new_feature` was never seen during collection, the ThresholdCache has no entry. With `block_unknown_endpoints: false` (default), it passes through. With `true`, it is blocked.

**Empty collection data** — switching to alert mode with no collected data means all endpoints are unknown. With default settings, everything passes through.

**Multiplier of 1.0** — enforces the exact observed maximum. Use > 1.0 for tolerance.

### Privacy in alert mode

Alert mode introduces two new locations where user-related data appears. Neither breaks the anonymization guarantee of the collection layer.

| Location | What is stored | Lifetime | Contains raw user ID? |
|---|---|---|---|
| `userpattern_request_events` (DB) | `anonymous_session_id` — HMAC hash of session/JWT | Retained until cleanup | No |
| `userpattern_violations` (DB) | `user_identifier` — HMAC hash of `"ModelType:user.id"` | Permanent | No |
| Cache store (Redis / memory) | Counter keys containing `user.id` | Expires automatically (2 min – 2 days) | Yes, but ephemeral |
| `ThresholdExceeded` exception | `user_id` attribute in the exception object | Request lifetime | Yes, in-memory only |
| `Rails.logger` | `user.id` in the log message (if `:log` action is enabled) | Depends on log retention | Yes |

**The database never contains a raw user ID.** Violations use a one-way HMAC hash (`user_identifier`), different from the `anonymous_session_id` used for collection, so the two cannot be correlated. Raw user IDs only exist in ephemeral contexts (cache keys, exceptions, logs) whose retention is controlled by the host application.

## Gem structure

```
userpattern/
├── app/
│   ├── controllers/user_pattern/dashboard_controller.rb
│   ├── models/user_pattern/
│   │   ├── request_event.rb
│   │   └── violation.rb
│   └── views/user_pattern/dashboard/
│       ├── index.html.erb
│       └── violations.html.erb
├── config/routes.rb
├── lib/
│   ├── userpattern.rb
│   ├── userpattern/
│   │   ├── anonymizer.rb           # HMAC anonymization
│   │   ├── buffer.rb               # Thread-safe in-memory buffer
│   │   ├── configuration.rb        # Configuration DSL
│   │   ├── controller_tracking.rb  # before_action + after_action concern
│   │   ├── engine.rb               # Rails Engine
│   │   ├── path_normalizer.rb      # URL normalization
│   │   ├── rate_limiter.rb         # Cache-backed rate limiting
│   │   ├── stats_calculator.rb     # SQL-agnostic stats computation
│   │   ├── threshold_cache.rb      # Periodic limit loader
│   │   ├── threshold_exceeded.rb   # Custom exception
│   │   ├── violation_recorder.rb   # Anonymized violation persistence
│   │   └── version.rb
│   ├── generators/userpattern/
│   │   ├── install_generator.rb
│   │   └── templates/
│   └── tasks/userpattern.rake
├── userpattern.gemspec
└── README.md
```

## License

MIT
