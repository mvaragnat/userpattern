# frozen_string_literal: true

module UserPattern
  class Configuration
    attr_accessor :tracked_models, :flush_interval, :buffer_size,
                  :retention_period, :dashboard_auth, :anonymous_salt,
                  :session_detection, :enabled, :ignored_paths

    def initialize
      @tracked_models = [{ name: "User", current_method: :current_user }]
      @flush_interval = 30
      @buffer_size = 100
      @retention_period = 30 # days
      @dashboard_auth = nil
      @anonymous_salt = nil
      @session_detection = :auto
      @enabled = true
      @ignored_paths = []
    end

    # DSL method: config.track "Admin", current_method: :current_admin
    def track(model_name, current_method: nil)
      method_name = current_method || :"current_#{model_name.to_s.underscore}"
      @tracked_models << { name: model_name.to_s, current_method: method_name }
    end
  end
end
