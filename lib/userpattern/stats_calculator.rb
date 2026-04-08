# frozen_string_literal: true

module UserPattern
  class StatsCalculator
    def self.compute_all
      new.compute_all
    end

    def compute_all
      load_groups.map { |row| build_stat(row) }
    end

    private

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
      span = time_span_seconds(first_seen, last_seen)

      {
        model_type: model_type,
        endpoint: endpoint,
        total_requests: total,
        total_sessions: sessions,
        avg_per_session: safe_divide(total, sessions),
        avg_per_minute: avg_rate(total, span, 60),
        max_per_minute: max_per_bucket(model_type, endpoint, :minute),
        max_per_hour: max_per_bucket(model_type, endpoint, :hour),
        max_per_day: max_per_bucket(model_type, endpoint, :day),
        first_seen_at: first_seen,
        last_seen_at: last_seen
      }
    end

    def max_per_bucket(model_type, endpoint, period)
      RequestEvent
        .where(model_type: model_type, endpoint: endpoint)
        .group(Arel.sql(bucket_expression(period)))
        .count
        .values
        .max || 0
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

    def time_span_seconds(first, last)
      return 1.0 if first.nil? || last.nil?

      span = (last.to_time - first.to_time).to_f
      span.positive? ? span : 1.0
    end

    def safe_divide(numerator, denominator)
      return 0.0 if denominator.nil? || denominator.zero?

      (numerator.to_f / denominator).round(2)
    end

    def avg_rate(total, span_seconds, period_seconds)
      periods = span_seconds / period_seconds.to_f
      return total.to_f.round(2) if periods < 1

      (total / periods).round(2)
    end
  end
end
