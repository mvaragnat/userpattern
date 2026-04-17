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
      it 'strips the entire query string' do
        expect(described_class.normalize('/admin?user_id=42')).to eq('/admin')
      end

      it 'strips query strings containing UUIDs' do
        path = '/admin?application_id=84ef5373-0e95-4477-bec0-08136fed079a'
        expect(described_class.normalize(path)).to eq('/admin')
      end

      it 'strips non-dynamic query values' do
        expect(described_class.normalize('/search?status=active')).to eq('/search')
      end

      it 'strips multiple query parameters' do
        path = '/api/items?id=123&status=active&token=abcdef1234567890'
        expect(described_class.normalize(path)).to eq('/api/items')
      end

      it 'groups different query variations into the same endpoint' do
        a = described_class.normalize('/demands/users?order=name_asc')
        b = described_class.normalize('/demands/users?order=name_desc')
        c = described_class.normalize('/demands/users')
        expect(a).to eq(b).and eq(c)
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
      it 'strips bare keys with no value' do
        expect(described_class.normalize('/search?flag')).to eq('/search')
      end

      it 'strips keys with empty values' do
        expect(described_class.normalize('/search?q=')).to eq('/search')
      end
    end
  end
end
