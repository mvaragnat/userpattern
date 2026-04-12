# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserPattern do
  describe '.configure' do
    it 'yields the configuration object to the block' do
      described_class.configure do |config|
        config.enabled = false
      end
      expect(described_class.configuration.enabled).to be false
    end
  end

  describe '.cleanup!' do
    it 'delegates to RequestEventCleanup.run!' do
      expect(UserPattern::RequestEventCleanup).to receive(:run!)
      described_class.cleanup!
    end
  end
end
