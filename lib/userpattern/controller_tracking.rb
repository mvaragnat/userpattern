# frozen_string_literal: true

require "userpattern/anonymizer"

module UserPattern
  module ControllerTracking
    extend ActiveSupport::Concern

    included do
      after_action :_userpattern_track_request
    end

    private

    def _userpattern_track_request
      return unless UserPattern.enabled?
      return if _userpattern_internal_request?

      UserPattern.configuration.tracked_models.each do |model_config|
        user = _userpattern_resolve(model_config[:current_method])
        next unless user

        UserPattern.buffer.push(
          model_type: model_config[:name],
          endpoint: "#{request.method} #{request.path}",
          anonymous_session_id: UserPattern::Anonymizer.anonymize(request),
          recorded_at: Time.current
        )
      end
    end

    def _userpattern_resolve(method_name)
      return nil unless respond_to?(method_name, true)

      send(method_name)
    rescue StandardError
      nil
    end

    def _userpattern_internal_request?
      self.class.name.to_s.start_with?("UserPattern::")
    end
  end
end
