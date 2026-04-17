# frozen_string_literal: true

require 'rails_helper'
require 'user_patterns/path_normalizer'

RSpec.describe UserPatterns::PathNormalizer do
  describe '.normalize' do
    context 'with numeric IDs in path segments' do
      it 'replaces a single numeric segment' do
        expect(described_class.normalize('/users/42')).to eq('/users/:id')
      end

      it 'replaces multiple numeric segments' do
        expect(described_class.normalize('/orders/123/items/456')).to eq('/orders/:id/items/:id')
      end

      it 'handles deeply nested paths' do
        path = '/adminv2/sinistres/2604921/member_ratio_remboursement'
        expect(described_class.normalize(path)).to eq('/adminv2/sinistres/:id/member_ratio_remboursement')
      end

      it 'aggregates different IDs to the same pattern' do
        a = described_class.normalize('/adminv2/sinistres/2604921/member_ratio_remboursement')
        b = described_class.normalize('/adminv2/sinistres/2605294/member_ratio_remboursement')
        expect(a).to eq(b)
      end
    end

    context 'with UUIDs in path segments' do
      it 'replaces a UUID segment' do
        path = '/api/resources/84ef5373-0e95-4477-bec0-08136fed079a'
        expect(described_class.normalize(path)).to eq('/api/resources/:id')
      end

      it 'handles uppercase UUIDs' do
        path = '/items/84EF5373-0E95-4477-BEC0-08136FED079A/details'
        expect(described_class.normalize(path)).to eq('/items/:id/details')
      end
    end

    context 'with hex tokens in path segments' do
      it 'replaces long hex strings (e.g. session tokens)' do
        path = '/verify/a1b2c3d4e5f6a7b8c9d0'
        expect(described_class.normalize(path)).to eq('/verify/:id')
      end

      it 'does not replace short hex-like strings that could be route names' do
        expect(described_class.normalize('/api/v2/abcdef')).to eq('/api/v2/abcdef')
      end
    end

    context 'with query string parameters' do
      it 'redacts numeric values' do
        expect(described_class.normalize('/admin?user_id=42')).to eq('/admin?user_id=:xxx')
      end

      it 'redacts UUID values' do
        path = '/admin?application_id=84ef5373-0e95-4477-bec0-08136fed079a'
        expect(described_class.normalize(path)).to eq('/admin?application_id=:xxx')
      end

      it 'preserves non-dynamic query values' do
        expect(described_class.normalize('/search?status=active')).to eq('/search?status=active')
      end

      it 'handles multiple query parameters' do
        path = '/api/items?id=123&status=active&token=abcdef1234567890'
        result = described_class.normalize(path)

        expect(result).to include('id=:xxx')
        expect(result).to include('status=active')
        expect(result).to include('token=:xxx')
      end

      it 'sorts query parameters for consistent aggregation' do
        a = described_class.normalize('/search?b=1&a=active')
        b = described_class.normalize('/search?a=active&b=1')
        expect(a).to eq(b)
      end
    end

    context 'with static paths' do
      it 'does not modify paths without dynamic segments' do
        expect(described_class.normalize('/api/v2/users')).to eq('/api/v2/users')
      end

      it 'handles root path' do
        expect(described_class.normalize('/')).to eq('/')
      end
    end

    context 'with edge-case query strings' do
      it 'preserves bare keys with no value' do
        expect(described_class.normalize('/search?flag')).to eq('/search?flag')
      end

      it 'preserves keys with empty values' do
        expect(described_class.normalize('/search?q=')).to eq('/search?q=')
      end
    end
  end
end
