# frozen_string_literal: true

require 'user_patterns/anonymizer'
require 'user_patterns/path_normalizer'

module UserPatterns
  module ControllerTracking
    extend ActiveSupport::Concern

    included do
      before_action :_user_patterns_check_rate_limit
      after_action :_user_patterns_track_request
    end

    private

    def _user_patterns_check_rate_limit
      return unless _user_patterns_should_check_rate_limit?

      _user_patterns_enforce_limits
    rescue UserPatterns::ThresholdExceeded => e
      _user_patterns_handle_violation(e)
    end

    def _user_patterns_should_check_rate_limit?
      UserPatterns.enabled? &&
        UserPatterns.configuration.alert_mode? &&
        !_user_patterns_internal_request? &&
        !_user_patterns_ignored_path? &&
        UserPatterns.rate_limiter
    end

    def _user_patterns_enforce_limits
      endpoint = "#{request.method} #{UserPatterns::PathNormalizer.normalize(request.fullpath)}"

      _user_patterns_each_matching_model do |model_config, user|
        UserPatterns.rate_limiter.check_and_increment!(user.id, model_config[:name], endpoint)
      end
    end

    def _user_patterns_handle_violation(violation)
      actions = UserPatterns.configuration.violation_actions

      _user_patterns_log_violation(violation) if actions.include?(:log)
      _user_patterns_record_violation(violation) if actions.include?(:record)
      UserPatterns.configuration.on_threshold_exceeded&.call(violation)
      UserPatterns.configuration.logout_method&.call(self) if actions.include?(:logout)

      raise violation if actions.include?(:raise)
    end

    def _user_patterns_log_violation(violation)
      Rails.logger.warn("[UserPatterns] #{violation.message}")
    end

    def _user_patterns_record_violation(violation)
      require 'user_patterns/violation_recorder'
      UserPatterns::ViolationRecorder.record!(violation)
    end

    def _user_patterns_track_request
      return unless UserPatterns.enabled?
      return if _user_patterns_internal_request?
      return if _user_patterns_ignored_path?

      _user_patterns_record_matching_models
    end

    def _user_patterns_record_matching_models
      _user_patterns_each_matching_model do |model_config, _user|
        UserPatterns.buffer.push(
          model_type: model_config[:name],
          endpoint: "#{request.method} #{UserPatterns::PathNormalizer.normalize(request.fullpath)}",
          anonymous_session_id: UserPatterns::Anonymizer.anonymize(request),
          recorded_at: Time.current
        )
      end
    end

    def _user_patterns_each_matching_model
      UserPatterns.configuration.tracked_models.each do |model_config|
        next unless UserPatterns.configuration.model_tracks_path?(model_config, request.path)

        user = _user_patterns_resolve(model_config[:current_method])
        next unless user

        yield model_config, user
      end
    end

    def _user_patterns_resolve(method_name)
      return nil unless respond_to?(method_name, true)

      send(method_name)
    rescue StandardError
      nil
    end

    def _user_patterns_internal_request?
      self.class.name.to_s.start_with?('UserPatterns::')
    end

    def _user_patterns_ignored_path?
      UserPatterns.configuration.ignored?(request.path)
    end
  end
end
