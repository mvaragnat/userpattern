# frozen_string_literal: true

module UserPatterns
  class StatsCalculator
    def self.compute_all
      new.compute_all
    end

    def compute_all
      load_groups
        .reject { |row| ignored_endpoint?(row[1]) }
        .map { |row| build_stat(row) }
    end

    private

    def ignored_endpoint?(endpoint)
      path = endpoint.split(' ', 2).last.to_s
      UserPatterns.configuration.ignored?(path)
    end

    def load_groups
      RequestEvent
        .group(:model_type, :endpoint)
        .pluck(
          :model_type,
          :endpoint,
          Arel.sql('COUNT(*)'),
          Arel.sql('COUNT(DISTINCT anonymous_session_id)'),
          Arel.sql('MIN(recorded_at)'),
          Arel.sql('MAX(recorded_at)')
        )
    end

    def build_stat(row)
      model_type, endpoint, total, sessions, first_seen, last_seen = row

      {
        model_type: model_type,
        endpoint: endpoint,
        total_requests: total,
        total_sessions: sessions,
        avg_per_session: safe_divide(total, sessions),
        first_seen_at: first_seen,
        last_seen_at: last_seen
      }.merge(session_rates(model_type, endpoint))
    end

    def session_rates(model_type, endpoint)
      minute_stats = per_session_bucket_stats(model_type, endpoint, :minute)
      hour_stats   = per_session_bucket_stats(model_type, endpoint, :hour)
      day_stats    = per_session_bucket_stats(model_type, endpoint, :day)

      {
        avg_per_minute: minute_stats[:avg],
        max_per_minute: minute_stats[:max],
        max_per_hour: hour_stats[:max],
        max_per_day: day_stats[:max]
      }
    end

    # Groups by (time_bucket, session) so each count represents a single
    # session's activity in one period — the baseline for per-user limits.
    def per_session_bucket_stats(model_type, endpoint, period)
      counts = RequestEvent
               .where(model_type: model_type, endpoint: endpoint)
               .group(Arel.sql(bucket_expression(period)), :anonymous_session_id)
               .count
               .values

      {
        max: counts.max || 0,
        avg: counts.empty? ? 0.0 : (counts.sum.to_f / counts.size).round(2)
      }
    end

    def bucket_expression(period)
      case connection_adapter
      when /postgres/
        pg_period = { minute: 'minute', hour: 'hour', day: 'day' }[period]
        "date_trunc('#{pg_period}', recorded_at)"
      when /mysql/
        fmt = { minute: '%Y-%m-%d %H:%i', hour: '%Y-%m-%d %H', day: '%Y-%m-%d' }[period]
        "DATE_FORMAT(recorded_at, '#{fmt}')"
      else
        fmt = { minute: '%Y-%m-%d %H:%M', hour: '%Y-%m-%d %H', day: '%Y-%m-%d' }[period]
        "strftime('#{fmt}', recorded_at)"
      end
    end

    def connection_adapter
      ActiveRecord::Base.connection.adapter_name.downcase
    end

    def safe_divide(numerator, denominator)
      return 0.0 if denominator.nil? || denominator.zero?

      (numerator.to_f / denominator).round(2)
    end
  end
end
