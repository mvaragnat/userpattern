# frozen_string_literal: true

require 'concurrent'
require 'userpattern/stats_calculator'

module UserPattern
  # Periodically loads observed max frequencies from the DB and builds
  # an in-memory lookup of limits (max * multiplier) per (model_type, endpoint).
  #
  # A Hash is used rather than a Set because we need associated limit values
  # per key — Hash#key? is already O(1), same as Set#include?.
  class ThresholdCache
    def initialize
      @limits = {}
      @mutex = Mutex.new
      safe_refresh
      start_refresh_timer
    end

    def limits_for(model_type, endpoint)
      @limits[[model_type, endpoint]]
    end

    def known_endpoint?(model_type, endpoint)
      @limits.key?([model_type, endpoint])
    end

    def all_limits
      @limits.dup
    end

    def refresh!
      new_limits = build_limits
      @mutex.synchronize { @limits = new_limits }
    end

    def shutdown
      @timer&.shutdown
    end

    private

    def build_limits
      multiplier = UserPattern.configuration.threshold_multiplier

      StatsCalculator.compute_all.each_with_object({}) do |stat, hash|
        key = [stat[:model_type], stat[:endpoint]]
        hash[key] = {
          per_minute: (stat[:max_per_minute] * multiplier).ceil,
          per_hour: (stat[:max_per_hour] * multiplier).ceil,
          per_day: (stat[:max_per_day] * multiplier).ceil
        }
      end
    end

    def safe_refresh
      refresh!
    rescue StandardError => e
      # :nocov:
      Rails.logger&.error("[UserPattern] Threshold refresh error: #{e.message}")
      # :nocov:
    end

    # :nocov:
    def start_refresh_timer
      @timer = Concurrent::TimerTask.new(
        execution_interval: UserPattern.configuration.threshold_refresh_interval
      ) { safe_refresh }
      @timer.execute
    end
    # :nocov:
  end
end
