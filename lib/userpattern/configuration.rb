# frozen_string_literal: true

module UserPattern
  class Configuration
    attr_reader :tracked_models

    attr_accessor :flush_interval, :buffer_size,
                  :retention_period, :dashboard_auth, :anonymous_salt,
                  :session_detection, :enabled, :ignored_paths

    def initialize
      @tracked_models = [{ name: 'User', current_method: :current_user }]
      @flush_interval = 30
      @buffer_size = 100
      @retention_period = 30 # days
      @dashboard_auth = nil
      @anonymous_salt = nil
      @session_detection = :auto
      @enabled = true
      @ignored_paths = []
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
  end
end
