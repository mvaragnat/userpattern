# frozen_string_literal: true

module UserPattern
  class Engine < ::Rails::Engine
    isolate_namespace UserPattern

    initializer 'userpattern.controller_tracking' do
      ActiveSupport.on_load(:action_controller_base) do
        require 'userpattern/controller_tracking'
        include UserPattern::ControllerTracking
      end

      ActiveSupport.on_load(:action_controller_api) do
        require 'userpattern/controller_tracking'
        include UserPattern::ControllerTracking
      end
    end

    # :nocov:
    initializer 'userpattern.default_salt' do
      config.after_initialize do
        UserPattern.configuration.anonymous_salt ||=
          Rails.application.secret_key_base&.byteslice(0, 32) || SecureRandom.hex(16)
      end
    end

    initializer 'userpattern.alert_mode' do
      config.after_initialize do
        UserPattern.start_alert_mode! if UserPattern.configuration.alert_mode?
      end
    end

    initializer 'userpattern.cleanup_task' do
      config.after_initialize do
        load File.expand_path('../tasks/userpattern.rake', __dir__) if defined?(Rake)
      end
    end
    # :nocov:
  end
end
