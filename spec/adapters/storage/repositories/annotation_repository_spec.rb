# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Storage::Repositories::AnnotationRepository do
  let(:storage) { instance_double(Shoko::Adapters::Storage::Repositories::Storage::AnnotationFileStore) }
  let(:repository) do
    described_class.new(
      file_writer: nil,
      storage: storage
    )
  end

  describe '#add_for_book' do
    it 'returns the newly added annotation deterministically by id diff' do
      book_path = '/tmp/book.epub'
      previous = [
        { 'id' => 'old', 'created_at' => '2026-01-10T00:00:00Z' },
      ]
      created = { id: 'new', created_at: '2025-01-10T00:00:00Z' }
      # Keep an older timestamp for the new annotation to prove we are not relying
      # on timestamp sorting.
      latest_old = { 'id' => 'latest-old', 'created_at' => '2026-02-10T00:00:00Z' }
      after = [previous.first, latest_old, created]

      allow(storage).to receive(:get).with(book_path).and_return(previous, after)
      allow(storage).to receive(:add).with(book_path, 'text', 'note', { start: 1, end: 2 }, 3, nil).and_return(true)

      result = repository.add_for_book(
        book_path,
        text: 'text',
        note: 'note',
        range: { start: 1, end: 2 },
        chapter_index: 3
      )

      expect(result).to eq(created)
    end

    it 'raises PersistenceError when underlying storage add fails' do
      book_path = '/tmp/book.epub'
      allow(storage).to receive(:get).with(book_path).and_return([])
      allow(storage).to receive(:add).and_return(false)

      expect do
        repository.add_for_book(
          book_path,
          text: 'text',
          note: 'note',
          range: { start: 1, end: 2 },
          chapter_index: 0
        )
      end.to raise_error(Shoko::Adapters::Storage::Repositories::BaseRepository::PersistenceError)
    end
  end

  describe '#update_note' do
    it 'returns true when storage updates successfully' do
      allow(storage).to receive(:update).with('/tmp/book.epub', 'id-1', 'new note').and_return(true)

      expect(repository.update_note('/tmp/book.epub', 'id-1', 'new note')).to be(true)
    end

    it 'returns false when storage does not update' do
      allow(storage).to receive(:update).with('/tmp/book.epub', 'id-1', 'new note').and_return(false)

      expect(repository.update_note('/tmp/book.epub', 'id-1', 'new note')).to be(false)
    end
  end
end
