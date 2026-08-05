# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/shoko/adapters/book_sources/pdf/parser/reader/stream_predictor'
require_relative '../../../../../lib/shoko/adapters/book_sources/pdf/parser/reader/dictionary_value_parser'

RSpec.describe Shoko::Adapters::BookSources::Pdf::Reader::StreamPredictor do
  it 'rejects attacker-controlled predictor geometry before allocation' do
    budget = Shoko::Adapters::BookSources::ImportBudget.new(path: 'wide.pdf', max_dimension_bytes: 8)
    predictor = described_class.new(dict_value: dict_value, import_budget: budget)
    header = '<< /DecodeParms << /Predictor 12 /Columns 1000000 /Colors 4 /BitsPerComponent 8 >> >>'

    expect { predictor.apply("\x00".b, header) }
      .to raise_error(Shoko::BookParseError, /PDF predictor (?:pixel|row) exceeds 8/)
  end

  let(:dict_value) { Shoko::Adapters::BookSources::Pdf::Reader::DictionaryValueParser.new.method(:parse) }
  let(:predictor) { described_class.new(dict_value: dict_value) }

  it 'returns data unchanged when no predictor is declared' do
    header = '<< /Filter /FlateDecode >>'
    data = [1, 2, 3, 4].pack('C*')

    expect(predictor.apply(data, header)).to eq(data)
  end

  it 'reverses a PNG Up predictor (the common xref-stream case)' do
    header = '<< /Filter /FlateDecode /DecodeParms << /Predictor 12 /Columns 3 >> >>'
    # Row 1: filter 0 (None) -> [10,20,30]; Row 2: filter 2 (Up) adds the row above.
    data = [0, 10, 20, 30, 2, 1, 2, 3].pack('C*')

    expect(predictor.apply(data, header).bytes).to eq([10, 20, 30, 11, 22, 33])
  end

  it 'reverses a PNG Sub predictor using the byte to the left' do
    header = '<< /DecodeParms << /Predictor 15 /Columns 4 >> >>'
    # filter 1 (Sub), bpp 1: each byte adds the reconstructed byte one to its left.
    data = [1, 5, 1, 1, 1].pack('C*')

    expect(predictor.apply(data, header).bytes).to eq([5, 6, 7, 8])
  end

  it 'reverses a TIFF predictor (Predictor 2)' do
    header = '<< /DecodeParms << /Predictor 2 /Columns 4 >> >>'
    data = [5, 1, 1, 1].pack('C*')

    expect(predictor.apply(data, header).bytes).to eq([5, 6, 7, 8])
  end
end
