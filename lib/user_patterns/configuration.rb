# frozen_string_literal: true

module UserPatterns
  class Configuration
    attr_reader :tracked_models

    attr_accessor :flush_interval, :buffer_size,
                  :retention_period, :anonymous_salt,
                  :session_detection, :enabled, :ignored_paths,
                  :mode, :threshold_multiplier, :threshold_refresh_interval,
                  :block_unknown_endpoints, :on_threshold_exceeded,
                  :violation_actions, :logout_method, :rate_limiter_store

    attr_writer :dashboard_auth

    def initialize
      @tracked_models = [{ name: 'User', current_method: :current_user }]
      @flush_interval = 30
      @buffer_size = 100
      @retention_period = 30
      @dashboard_auth = nil
      @anonymous_salt = nil
      @session_detection = :auto
      @enabled = true
      @ignored_paths = []
      initialize_alert_defaults
    end

    def alert_mode?
      @mode == :alert
    end

    def dashboard_auth
      @dashboard_auth || default_dashboard_auth
    end

    def tracked_models=(list)
      @tracked_models = list.map do |entry|
        name = entry[:name].to_s
        method = entry[:current_method] || :"current_#{name.underscore}"
        { name: name, current_method: method }
      end
    end

    def ignored?(path)
      ignored_paths.any? do |pattern|
        case pattern
        when Regexp then pattern.match?(path)
        when String then pattern == path
        end
      end
    end

    private

    def initialize_alert_defaults
      @mode = :collection
      @threshold_multiplier = 1.5
      @threshold_refresh_interval = 300
      @block_unknown_endpoints = false
      @on_threshold_exceeded = nil
      @violation_actions = [:raise]
      @logout_method = nil
      @rate_limiter_store = nil
    end

    def default_dashboard_auth
      user = ENV.fetch('USER_PATTERNS_DASHBOARD_USER', nil)
      pass = ENV.fetch('USER_PATTERNS_DASHBOARD_PASSWORD', nil)
      return locked_dashboard_auth unless user && pass

      basic_auth_lambda(user, pass)
    end

    def locked_dashboard_auth
      lambda {
        render plain: 'Dashboard locked. Set USER_PATTERNS_DASHBOARD_USER and ' \
                      'USER_PATTERNS_DASHBOARD_PASSWORD environment variables, ' \
                      'or configure a custom dashboard_auth.',
               status: :forbidden
      }
    end

    def basic_auth_lambda(user, pass)
      lambda {
        authenticate_or_request_with_http_basic('UserPatterns') do |provided_user, provided_pass|
          ActiveSupport::SecurityUtils.secure_compare(provided_user, user) &
            ActiveSupport::SecurityUtils.secure_compare(provided_pass, pass)
        end
      }
    end
  end
end
