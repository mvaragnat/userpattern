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
end
