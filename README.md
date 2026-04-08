# UserPattern

Anonymized usage-pattern analysis for Rails applications.

UserPattern plugs into any Rails app as an engine. It intercepts requests from authenticated users, collects per-endpoint frequency statistics, and presents a sortable dashboard — all without ever storing a user identifier.

## Features

- **Multi-model** — track `User`, `Admin`, or any authenticatable model.
- **Devise + JWT compatible** — auto-detects session cookies and `Authorization` headers.
- **Fully anonymized** — impossible to trace actions back to a specific user (daily-rotating HMAC salt).
- **Minimal performance impact** — in-memory buffer, async batch writes.
- **Built-in dashboard** — sortable HTML table, filterable by model type.
- **Automatic cleanup** — rake task to purge expired data.

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
2. A migration for the `userpattern_request_events` table
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

  # Dashboard authentication (see "Securing the dashboard" section below)
  config.dashboard_auth = nil

  # Enable / disable tracking globally
  config.enabled = true
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

### Buffer architecture

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

It displays, per model type:

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

All columns are sortable (click the header).

## Securing the dashboard

**The dashboard is unprotected by default.** You must configure authentication.

### Option 1: HTTP Basic Auth

```ruby
config.dashboard_auth = -> {
  authenticate_or_request_with_http_basic("UserPattern") do |user, pass|
    ActiveSupport::SecurityUtils.secure_compare(user, "admin") &
      ActiveSupport::SecurityUtils.secure_compare(pass, ENV["USERPATTERN_PASSWORD"])
  end
}
```

### Option 2: Devise (admin-only)

```ruby
config.dashboard_auth = -> {
  redirect_to main_app.root_path, alert: "Access denied" unless current_user&.admin?
}
```

### Option 3: Rails routing constraint

```ruby
# config/routes.rb
authenticate :user, ->(u) { u.admin? } do
  mount UserPattern::Engine, at: "/userpatterns"
end
```

### Option 4: IP allowlist

```ruby
config.dashboard_auth = -> {
  head :forbidden unless request.remote_ip.in?(%w[127.0.0.1 ::1])
}
```

## Roadmap (not yet implemented)

**Threshold alerts** — define per-endpoint thresholds (e.g. max 10 requests/minute) and get notified when a logged-in user exceeds them. The current schema (individual events with timestamps) supports this without migration changes.

## Gem structure

```
userpattern/
├── app/
│   ├── controllers/user_pattern/dashboard_controller.rb
│   ├── models/user_pattern/request_event.rb
│   └── views/user_pattern/dashboard/index.html.erb
├── config/routes.rb
├── lib/
│   ├── userpattern.rb
│   ├── userpattern/
│   │   ├── anonymizer.rb          # HMAC anonymization
│   │   ├── buffer.rb              # Thread-safe in-memory buffer
│   │   ├── configuration.rb       # Configuration DSL
│   │   ├── controller_tracking.rb # after_action concern
│   │   ├── engine.rb              # Rails Engine
│   │   ├── stats_calculator.rb    # SQL-agnostic stats computation
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
