# frozen_string_literal: true

require 'userpattern/version'
require 'userpattern/configuration'

module UserPattern
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def buffer
      @buffer ||= begin
        require 'userpattern/buffer'
        Buffer.new
      end
    end

    attr_reader :threshold_cache, :rate_limiter

    def start_alert_mode!
      require 'userpattern/threshold_cache'
      require 'userpattern/rate_limiter'

      @threshold_cache = ThresholdCache.new
      store = configuration.rate_limiter_store || default_cache_store
      @rate_limiter = RateLimiter.new(store: store, threshold_cache: @threshold_cache)
    end

    def enabled?
      configuration.enabled
    end

    def cleanup!
      require 'userpattern/request_event_cleanup'
      RequestEventCleanup.run!
    end

    def reset!
      @buffer&.shutdown
      @threshold_cache&.shutdown
      @configuration = Configuration.new
      @buffer = nil
      @threshold_cache = nil
      @rate_limiter = nil
    end

    private

    def default_cache_store
      if defined?(Rails) && Rails.respond_to?(:cache) && Rails.cache
        Rails.cache
      else
        ActiveSupport::Cache::MemoryStore.new
      end
    end
  end
end

# :nocov:
require 'userpattern/engine' if defined?(Rails::Engine)
# :nocov:
