# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserPattern::Configuration do
  subject(:config) { described_class.new }

  describe 'defaults' do
    it 'tracks User via current_user' do
      expect(config.tracked_models).to eq([{ name: 'User', current_method: :current_user }])
    end

    it 'uses auto session detection' do
      expect(config.session_detection).to eq(:auto)
    end

    it 'is enabled' do
      expect(config.enabled).to be true
    end

    it 'has no ignored paths' do
      expect(config.ignored_paths).to eq([])
    end

    it 'retains data for 30 days' do
      expect(config.retention_period).to eq(30)
    end

    it 'buffers 100 events before flushing' do
      expect(config.buffer_size).to eq(100)
    end

    it 'flushes every 30 seconds' do
      expect(config.flush_interval).to eq(30)
    end

    it 'defaults to collection mode' do
      expect(config.mode).to eq(:collection)
      expect(config.alert_mode?).to be false
    end

    it 'defaults violation_actions to [:raise]' do
      expect(config.violation_actions).to eq([:raise])
    end

    it 'defaults threshold_multiplier to 1.5' do
      expect(config.threshold_multiplier).to eq(1.5)
    end
  end

  describe '#alert_mode?' do
    it 'returns true when mode is :alert' do
      config.mode = :alert
      expect(config.alert_mode?).to be true
    end

    it 'returns false when mode is :collection' do
      expect(config.alert_mode?).to be false
    end
  end

  describe '#dashboard_auth' do
    it 'returns a 403 proc when no env vars are set' do
      expect(config.dashboard_auth).to be_a(Proc)
    end

    it 'returns a custom proc when explicitly set' do
      custom = -> { 'custom' }
      config.dashboard_auth = custom
      expect(config.dashboard_auth).to eq(custom)
    end
  end

  describe '#ignored?' do
    it 'returns false when ignored_paths is empty' do
      expect(config.ignored?('/health')).to be false
    end

    it 'matches an exact string' do
      config.ignored_paths = ['/health', '/up']
      expect(config.ignored?('/health')).to be true
      expect(config.ignored?('/up')).to be true
      expect(config.ignored?('/other')).to be false
    end

    it 'does not partial-match strings' do
      config.ignored_paths = ['/health']
      expect(config.ignored?('/health/deep')).to be false
    end

    it 'matches a regexp' do
      config.ignored_paths = [%r{\A/api/internal}]
      expect(config.ignored?('/api/internal/status')).to be true
      expect(config.ignored?('/api/public')).to be false
    end
  end

  describe '#tracked_models=' do
    it 'normalizes entries with explicit current_method' do
      config.tracked_models = [{ name: 'Admin', current_method: :current_admin }]
      expect(config.tracked_models).to eq([{ name: 'Admin', current_method: :current_admin }])
    end

    it 'infers current_method from underscored name' do
      config.tracked_models = [{ name: 'Admin' }]
      expect(config.tracked_models).to eq([{ name: 'Admin', current_method: :current_admin }])
    end

    it 'handles CamelCase model names' do
      config.tracked_models = [{ name: 'ApiClient' }]
      expect(config.tracked_models).to eq([{ name: 'ApiClient', current_method: :current_api_client }])
    end

    it 'accepts multiple models' do
      config.tracked_models = [
        { name: 'User' },
        { name: 'Admin', current_method: :current_admin_user }
      ]

      expect(config.tracked_models).to contain_exactly(
        { name: 'User', current_method: :current_user },
        { name: 'Admin', current_method: :current_admin_user }
      )
    end
  end
end
