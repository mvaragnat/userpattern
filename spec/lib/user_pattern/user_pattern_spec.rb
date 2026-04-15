# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserPattern do
  describe '.configure' do
    it 'yields the configuration object to the block' do
      described_class.configure do |config|
        config.enabled = false
      end
      expect(described_class.configuration.enabled).to be false
    end
  end

  describe '.cleanup!' do
    it 'delegates to RequestEventCleanup.run!' do
      allow(UserPattern::RequestEventCleanup).to receive(:run!)
      described_class.cleanup!
      expect(UserPattern::RequestEventCleanup).to have_received(:run!)
    end
  end

  describe '.start_alert_mode!' do
    after { described_class.reset! }

    it 'creates a threshold_cache and rate_limiter' do
      described_class.start_alert_mode!

      expect(described_class.threshold_cache).to be_a(UserPattern::ThresholdCache)
      expect(described_class.rate_limiter).to be_a(UserPattern::RateLimiter)
    end

    it 'uses the configured rate_limiter_store' do
      custom_store = ActiveSupport::Cache::MemoryStore.new
      described_class.configuration.rate_limiter_store = custom_store
      described_class.start_alert_mode!

      expect(described_class.rate_limiter).to be_a(UserPattern::RateLimiter)
    end

    it 'falls back to Rails.cache when no store is configured' do
      described_class.configuration.rate_limiter_store = nil
      described_class.start_alert_mode!

      expect(described_class.rate_limiter).to be_a(UserPattern::RateLimiter)
    end

    it 'falls back to MemoryStore when Rails.cache is nil' do
      described_class.configuration.rate_limiter_store = nil
      allow(Rails).to receive(:cache).and_return(nil)
      described_class.start_alert_mode!

      expect(described_class.rate_limiter).to be_a(UserPattern::RateLimiter)
    end
  end

  describe '.reset!' do
    it 'clears threshold_cache and rate_limiter' do
      described_class.start_alert_mode!
      described_class.reset!

      expect(described_class.threshold_cache).to be_nil
      expect(described_class.rate_limiter).to be_nil
    end
  end
end
