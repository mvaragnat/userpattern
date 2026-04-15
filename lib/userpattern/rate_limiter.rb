# frozen_string_literal: true

require 'userpattern/threshold_exceeded'

module UserPattern
  # Checks per-user request rates against the limits from ThresholdCache.
  # Counters are stored in an ActiveSupport::Cache::Store (same interface
  # as Rack::Attack), giving multi-process support via Redis/Memcached.
  class RateLimiter
    PERIODS = {
      minute: { format: '%Y-%m-%dT%H:%M', ttl: 120 },
      hour: { format: '%Y-%m-%dT%H', ttl: 7_200 },
      day: { format: '%Y-%m-%d', ttl: 172_800 }
    }.freeze

    def initialize(store:, threshold_cache:)
      @store = store
      @threshold_cache = threshold_cache
    end

    def check_and_increment!(user_id, model_type, endpoint)
      limits = @threshold_cache.limits_for(model_type, endpoint)

      if limits.nil?
        return unless UserPattern.configuration.block_unknown_endpoints

        raise_threshold_exceeded(endpoint, user_id, model_type, 'unknown', 1, 0)
      end

      PERIODS.each do |period, config|
        check_period!(user_id, model_type, endpoint, period, config[:format], limits)
      end
    end

    private

    def check_period!(user_id, model_type, endpoint, period, time_format, limits)
      limit = limits[:"per_#{period}"]
      return unless limit&.positive?

      key = cache_key(user_id, endpoint, period, Time.current.strftime(time_format))
      count = increment_counter(key, PERIODS[period][:ttl])

      return unless count > limit

      raise_threshold_exceeded(endpoint, user_id, model_type, period.to_s, count, limit)
    end

    def raise_threshold_exceeded(endpoint, user_id, model_type, period, count, limit)
      raise ThresholdExceeded.new(
        endpoint: endpoint, user_id: user_id, model_type: model_type,
        period: period, count: count, limit: limit
      )
    end

    def increment_counter(key, ttl)
      count = @store.increment(key, 1, expires_in: ttl)
      return count if count

      @store.write(key, 1, expires_in: ttl)
      1
    end

    def cache_key(user_id, endpoint, period, bucket)
      "userpattern:#{user_id}:#{endpoint}:#{period}:#{bucket}"
    end
  end
end
