# frozen_string_literal: true

require 'rails_helper'

FakeSession = Struct.new(:id)
FakeRequest = Struct.new(:headers, :session, :remote_ip, keyword_init: true)

RSpec.describe UserPattern::Anonymizer do
  let(:session) { FakeSession.new('session_abc') }
  let(:headers) { {} }
  let(:request) { FakeRequest.new(headers: headers, session: session, remote_ip: '10.0.0.1') }

  describe '.anonymize' do
    it 'returns a 16-character hex string' do
      expect(described_class.anonymize(request)).to match(/\A[0-9a-f]{16}\z/)
    end

    it 'is deterministic for the same input' do
      first = described_class.anonymize(request)
      second = described_class.anonymize(request)
      expect(first).to eq(second)
    end

    it 'varies when the salt changes' do
      first = described_class.anonymize(request)
      UserPattern.configuration.anonymous_salt = 'completely_different_salt_value!!'
      second = described_class.anonymize(request)

      expect(first).not_to eq(second)
    end

    it 'varies for different sessions' do
      first = described_class.anonymize(request)
      other = FakeRequest.new(headers: headers, session: FakeSession.new('session_xyz'), remote_ip: '10.0.0.1')
      second = described_class.anonymize(other)

      expect(first).not_to eq(second)
    end
  end

  describe 'auto-detection' do
    context 'with Authorization header' do
      let(:headers) { { 'Authorization' => 'Bearer jwt.token.here' } }

      it 'produces a different fingerprint than session-based' do
        session_request = FakeRequest.new(headers: {}, session: session, remote_ip: '10.0.0.1')
        expect(described_class.anonymize(request)).not_to eq(described_class.anonymize(session_request))
      end
    end

    context 'with session only' do
      let(:headers) { {} }

      it 'uses session id' do
        expect(described_class.anonymize(request)).to be_present
      end
    end

    context 'with no session and no header' do
      let(:session) { FakeSession.new(nil) }

      it 'falls back to remote IP' do
        expect(described_class.anonymize(request)).to be_present
      end

      it 'varies by IP' do
        other = FakeRequest.new(headers: {}, session: FakeSession.new(nil), remote_ip: '10.0.0.2')
        expect(described_class.anonymize(request)).not_to eq(described_class.anonymize(other))
      end
    end
  end

  describe 'configured detection modes' do
    it ':session always uses the session id' do
      UserPattern.configuration.session_detection = :session
      req_with_auth = FakeRequest.new(
        headers: { 'Authorization' => 'Bearer token' }, session: session, remote_ip: '10.0.0.1'
      )
      req_without_auth = FakeRequest.new(headers: {}, session: session, remote_ip: '10.0.0.1')

      expect(described_class.anonymize(req_with_auth)).to eq(described_class.anonymize(req_without_auth))
    end

    it ':header always uses the Authorization header' do
      UserPattern.configuration.session_detection = :header
      result = described_class.anonymize(
        FakeRequest.new(headers: { 'Authorization' => 'Bearer abc' }, session: session, remote_ip: '10.0.0.1')
      )
      expect(result).to match(/\A[0-9a-f]{16}\z/)
    end

    it 'accepts a custom Proc' do
      UserPattern.configuration.session_detection = ->(req) { "custom_#{req.remote_ip}" }

      result_a = described_class.anonymize(request)
      result_b = described_class.anonymize(
        FakeRequest.new(headers: {}, session: session, remote_ip: '10.0.0.2')
      )

      expect(result_a).not_to eq(result_b)
    end
  end
end
