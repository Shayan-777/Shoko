# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Events::EventFactory do
  let(:wall_clock) { instance_double('WallClock', utc_now: Time.utc(2024, 1, 2, 3, 4, 5)) }
  let(:id_generator) { instance_double('IdGenerator', uuid: 'evt-123') }
  let(:bookmark) { Struct.new(:chapter_index, :line_offset).new(1, 10) }

  subject(:factory) { described_class.new(wall_clock: wall_clock, id_generator: id_generator) }

  it 'builds domain events with injected metadata' do
    event = factory.build(
      Shoko::Core::Events::BookmarkAdded,
      book_path: '/books/a.epub',
      bookmark: bookmark
    )

    expect(event.event_id).to eq('evt-123')
    expect(event.occurred_at).to eq(Time.utc(2024, 1, 2, 3, 4, 5))
    expect(event.book_path).to eq('/books/a.epub')
  end
end
