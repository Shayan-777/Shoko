# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'zlib'

RSpec.describe Shoko::Adapters::BookSources::ImportBudget do
  it 'rejects a source before reading beyond its configured byte ceiling' do
    Tempfile.create('oversized-book') do |file|
      file.binmode
      file.write('x' * 9)
      file.flush
      budget = described_class.new(path: file.path, max_source_bytes: 8)

      expect { budget.read_binary }.to raise_error(Shoko::BookParseError, /source exceeds 8 bytes/)
    end
  end

  it 'rejects a compressed stream before retaining output beyond the item ceiling' do
    compressed = Zlib::Deflate.deflate('a' * 128)
    budget = described_class.new(
      path: 'hostile.pdf',
      max_expanded_item_bytes: 64,
      max_expanded_bytes: 256
    )

    expect { budget.inflate(compressed, label: 'PDF stream') }
      .to raise_error(Shoko::BookParseError, /PDF stream exceeds 64 bytes/)
  end

  it 'accounts expanded data across independent records' do
    budget = described_class.new(
      path: 'hostile.mobi',
      max_expanded_item_bytes: 64,
      max_expanded_bytes: 100
    )

    budget.consume_expanded!(60, label: 'record 1')
    expect { budget.consume_expanded!(50, label: 'record 2') }
      .to raise_error(Shoko::BookParseError, /aggregate expanded-data budget/)
  end

  it 'bounds resources, parser structure, nesting, and decoded dimensions' do
    budget = described_class.new(
      path: 'hostile.fb2',
      max_resource_item_bytes: 4,
      max_resource_bytes: 6,
      max_structural_units: 2,
      max_decode_operations: 2,
      max_nesting: 2,
      max_dimension_bytes: 8
    )

    expect { budget.consume_resource!(5) }.to raise_error(Shoko::BookParseError, /embedded resource exceeds/)
    budget.consume_structure!(2)
    expect { budget.consume_structure! }.to raise_error(Shoko::BookParseError, /document structure exceeds/)
    budget.consume_decode_operations!(2)
    expect { budget.consume_decode_operations!(1) }.to raise_error(Shoko::BookParseError, /work budget/)
    expect { budget.check_nesting!(3) }.to raise_error(Shoko::BookParseError, /document nesting exceeds/)
    expect { budget.check_dimension!(9) }.to raise_error(Shoko::BookParseError, /decoded row exceeds/)
  end
end
