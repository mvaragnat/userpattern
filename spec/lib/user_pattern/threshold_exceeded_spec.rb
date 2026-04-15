# frozen_string_literal: true

require 'rails_helper'
require 'userpattern/threshold_exceeded'

RSpec.describe UserPattern::ThresholdExceeded do
  subject(:error) do
    described_class.new(
      endpoint: 'GET /api/users',
      user_id: 42,
      model_type: 'User',
      period: 'minute',
      count: 9,
      limit: 8
    )
  end

  it 'exposes all attributes' do
    expect(error.endpoint).to eq('GET /api/users')
    expect(error.user_id).to eq(42)
    expect(error.model_type).to eq('User')
    expect(error.period).to eq('minute')
    expect(error.count).to eq(9)
    expect(error.limit).to eq(8)
  end

  it 'builds a descriptive message' do
    expect(error.message).to include('GET /api/users')
    expect(error.message).to include('9/minute')
    expect(error.message).to include('max: 8')
    expect(error.message).to include('User#42')
  end

  it 'is a StandardError' do
    expect(error).to be_a(StandardError)
  end
end
