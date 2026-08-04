# frozen_string_literal: true

require 'spec_helper'
require 'shoko/core/services/prepagination_status'

RSpec.describe Shoko::Core::Services::PrepaginationStatus do
  let(:paths) { ['/a', '/b', '/c', '/d'] }

  describe '.for_path' do
    it 'treats every book as ready when no batch is running' do
      expect(described_class.for_path('/b', paths: paths, done: 1, active: false)).to eq(:ready)
    end

    it 'treats a book outside the batch as ready' do
      expect(described_class.for_path('/z', paths: paths, done: 1, active: true)).to eq(:ready)
    end

    it 'marks already-processed books done, the current one in progress, the rest queued' do
      # done = 2 -> /a, /b finished; /c is building; /d waits.
      expect(described_class.for_path('/a', paths: paths, done: 2, active: true)).to eq(:done)
      expect(described_class.for_path('/b', paths: paths, done: 2, active: true)).to eq(:done)
      expect(described_class.for_path('/c', paths: paths, done: 2, active: true)).to eq(:in_progress)
      expect(described_class.for_path('/d', paths: paths, done: 2, active: true)).to eq(:queued)
    end

    it 'returns ready for a nil path' do
      expect(described_class.for_path(nil, paths: paths, done: 0, active: true)).to eq(:ready)
    end
  end

  describe '.openable?' do
    it 'is true only for ready or done' do
      expect(described_class.openable?(:ready)).to be(true)
      expect(described_class.openable?(:done)).to be(true)
      expect(described_class.openable?(:in_progress)).to be(false)
      expect(described_class.openable?(:queued)).to be(false)
    end
  end
end
