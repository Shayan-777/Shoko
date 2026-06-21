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
      allow(storage).to receive(:add).with(
        book_path,
        an_instance_of(Shoko::Core::Models::AnnotationDraft)
      ).and_return(true)

      result = repository.add_for_book(
        book_path,
        text: 'text',
        note: 'note',
        anchor: { quote: 'text' },
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
          anchor: { quote: 'text' },
          chapter_index: 0
        )
      end.to raise_error(Shoko::Adapters::Storage::Repositories::BaseRepository::PersistenceError)
    end

    # The persistence failure must stay inside the domain error family so the
    # `rescue Shoko::Error` boundaries above the repositories actually contain
    # it instead of letting it unwind the reader/menu run loop.
    it 'raises a failure that is a Shoko::Error' do
      book_path = '/tmp/book.epub'
      allow(storage).to receive(:get).with(book_path).and_return([])
      allow(storage).to receive(:add).and_return(false)

      raised = nil
      begin
        repository.add_for_book(book_path, text: 't', note: 'n', anchor: { quote: 't' }, chapter_index: 0)
      rescue Shoko::Error => e
        raised = e
      end

      expect(raised).to be_a(Shoko::Adapters::Storage::Repositories::BaseRepository::PersistenceError)
    end
  end

  describe '#update_note' do
    it 'returns the normalized annotation when storage updates successfully' do
      allow(storage).to receive(:update).with('/tmp/book.epub', 'id-1', 'new note').and_return(
        { 'id' => 'id-1', 'note' => 'new note' }
      )

      expect(repository.update_note('/tmp/book.epub', 'id-1', 'new note')).to eq(id: 'id-1', note: 'new note')
    end

    it 'returns nil when storage does not update' do
      allow(storage).to receive(:update).with('/tmp/book.epub', 'id-1', 'new note').and_return(nil)

      expect(repository.update_note('/tmp/book.epub', 'id-1', 'new note')).to be_nil
    end
  end
end
