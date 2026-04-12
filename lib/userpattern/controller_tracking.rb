# frozen_string_literal: true

require 'userpattern/anonymizer'
require 'userpattern/path_normalizer'

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
      return if _userpattern_ignored_path?

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

    def _userpattern_ignored_path?
      path = request.path
      UserPattern.configuration.ignored_paths.any? do |pattern|
        case pattern
        when Regexp then pattern.match?(path)
        when String then pattern == path
        end
      end
    end
  end
end
