# frozen_string_literal: true

require 'rails_helper'
require 'userpattern/rate_limiter'

RSpec.describe UserPattern::RateLimiter do
  let(:threshold_cache) { instance_double(UserPattern::ThresholdCache) }
  let(:store) { ActiveSupport::Cache::MemoryStore.new }
  let(:limiter) { described_class.new(store: store, threshold_cache: threshold_cache) }

  before do
    allow(threshold_cache).to receive(:limits_for)
      .with('User', 'GET /api/test')
      .and_return({ per_minute: 3, per_hour: 10, per_day: 50 })
  end

  describe '#check_and_increment!' do
    it 'allows requests under the limit' do
      expect do
        limiter.check_and_increment!(42, 'User', 'GET /api/test')
      end.not_to raise_error
    end

    it 'raises ThresholdExceeded when minute limit is exceeded' do
      3.times { limiter.check_and_increment!(42, 'User', 'GET /api/test') }

      expect do
        limiter.check_and_increment!(42, 'User', 'GET /api/test')
      end.to raise_error(UserPattern::ThresholdExceeded) { |e|
        expect(e.period).to eq('minute')
        expect(e.count).to eq(4)
        expect(e.limit).to eq(3)
      }
    end

    it 'tracks users independently' do
      3.times { limiter.check_and_increment!(42, 'User', 'GET /api/test') }

      expect do
        limiter.check_and_increment!(99, 'User', 'GET /api/test')
      end.not_to raise_error
    end

    context 'with an unknown endpoint' do
      before do
        allow(threshold_cache).to receive(:limits_for)
          .with('User', 'GET /unknown')
          .and_return(nil)
      end

      it 'passes through when block_unknown_endpoints is false' do
        UserPattern.configuration.block_unknown_endpoints = false

        expect do
          limiter.check_and_increment!(42, 'User', 'GET /unknown')
        end.not_to raise_error
      end

      it 'raises when block_unknown_endpoints is true' do
        UserPattern.configuration.block_unknown_endpoints = true

        expect do
          limiter.check_and_increment!(42, 'User', 'GET /unknown')
        end.to raise_error(UserPattern::ThresholdExceeded)
      end
    end
  end
end
