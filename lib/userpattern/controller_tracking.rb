# frozen_string_literal: true

require 'userpattern/anonymizer'
require 'userpattern/path_normalizer'

module UserPattern
  module ControllerTracking
    extend ActiveSupport::Concern

    included do
      before_action :_userpattern_check_rate_limit
      after_action :_userpattern_track_request
    end

    private

    def _userpattern_check_rate_limit
      return unless _userpattern_should_check_rate_limit?

      _userpattern_enforce_limits
    rescue UserPattern::ThresholdExceeded => e
      _userpattern_handle_violation(e)
    end

    def _userpattern_should_check_rate_limit?
      UserPattern.enabled? &&
        UserPattern.configuration.alert_mode? &&
        !_userpattern_internal_request? &&
        UserPattern.rate_limiter
    end

    def _userpattern_enforce_limits
      endpoint = "#{request.method} #{UserPattern::PathNormalizer.normalize(request.fullpath)}"

      UserPattern.configuration.tracked_models.each do |model_config|
        user = _userpattern_resolve(model_config[:current_method])
        next unless user

        UserPattern.rate_limiter.check_and_increment!(user.id, model_config[:name], endpoint)
      end
    end

    def _userpattern_handle_violation(violation)
      actions = UserPattern.configuration.violation_actions

      _userpattern_log_violation(violation) if actions.include?(:log)
      _userpattern_record_violation(violation) if actions.include?(:record)
      UserPattern.configuration.on_threshold_exceeded&.call(violation)
      UserPattern.configuration.logout_method&.call(self) if actions.include?(:logout)

      raise violation if actions.include?(:raise)
    end

    def _userpattern_log_violation(violation)
      Rails.logger.warn("[UserPattern] #{violation.message}")
    end

    def _userpattern_record_violation(violation)
      require 'userpattern/violation_recorder'
      UserPattern::ViolationRecorder.record!(violation)
    end

    def _userpattern_track_request
      return unless UserPattern.enabled?
      return if _userpattern_internal_request?

      _userpattern_record_matching_models
    end

    def _userpattern_record_matching_models
      UserPattern.configuration.tracked_models.each do |model_config|
        user = _userpattern_resolve(model_config[:current_method])
        next unless user

        UserPattern.buffer.push(
          model_type: model_config[:name],
          endpoint: "#{request.method} #{UserPattern::PathNormalizer.normalize(request.fullpath)}",
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
      self.class.name.to_s.start_with?('UserPattern::')
    end
  end
end
