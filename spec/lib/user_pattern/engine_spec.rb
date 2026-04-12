# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserPattern::Engine do
  describe 'controller_tracking initializer' do
    it 'includes ControllerTracking in ActionController::API controllers' do
      api_class = Class.new(ActionController::API)
      ActiveSupport.run_load_hooks(:action_controller_api, api_class)
      expect(api_class.ancestors).to include(UserPattern::ControllerTracking)
    end
  end

  describe 'alert_mode initializer' do
    it 'does not start alert mode in collection mode' do
      expect(UserPattern.threshold_cache).to be_nil
      expect(UserPattern.rate_limiter).to be_nil
    end
  end
end
