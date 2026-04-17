# frozen_string_literal: true

require 'rails_helper'
require 'user_patterns/rate_limiter'

RSpec.describe UserPatterns::RateLimiter do
  let(:threshold_cache) { instance_double(UserPatterns::ThresholdCache) }
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
      end.to raise_error(UserPatterns::ThresholdExceeded) { |e|
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
        UserPatterns.configuration.block_unknown_endpoints = false

        expect do
          limiter.check_and_increment!(42, 'User', 'GET /unknown')
        end.not_to raise_error
      end

      it 'raises when block_unknown_endpoints is true' do
        UserPatterns.configuration.block_unknown_endpoints = true

        expect do
          limiter.check_and_increment!(42, 'User', 'GET /unknown')
        end.to raise_error(UserPatterns::ThresholdExceeded)
      end
    end

    context 'when a period limit is nil' do
      before do
        allow(threshold_cache).to receive(:limits_for)
          .with('User', 'GET /partial')
          .and_return({ per_minute: nil, per_hour: 10, per_day: 50 })
      end

      it 'skips the nil-limit period and checks others' do
        expect do
          limiter.check_and_increment!(42, 'User', 'GET /partial')
        end.not_to raise_error
      end
    end

    context 'when cache store returns nil on increment' do
      let(:nil_store) { ActiveSupport::Cache::MemoryStore.new }
      let(:nil_limiter) { described_class.new(store: nil_store, threshold_cache: threshold_cache) }

      it 'falls back to write and returns 1' do
        allow(nil_store).to receive(:increment).and_return(nil)
        allow(nil_store).to receive(:write)

        expect do
          nil_limiter.check_and_increment!(42, 'User', 'GET /api/test')
        end.not_to raise_error
        expect(nil_store).to have_received(:write).at_least(:once)
      end
    end
  end
end
