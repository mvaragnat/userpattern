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

    def enabled?
      configuration.enabled
    end

    def cleanup!
      require 'userpattern/request_event_cleanup'
      RequestEventCleanup.run!
    end

    def reset!
      @buffer&.shutdown
      @configuration = Configuration.new
      @buffer = nil
    end
  end
end

# :nocov:
require 'userpattern/engine' if defined?(Rails::Engine)
# :nocov:
