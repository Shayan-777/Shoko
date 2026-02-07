# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::BookFormats::Pdf::PdfReader do
  def build_reader(data, xref)
    reader = described_class.allocate
    reader.instance_variable_set(:@data, data.b)
    reader.instance_variable_set(:@xref, xref)
    reader.instance_variable_set(:@trailer, {})
    reader.instance_variable_set(:@object_cache, {})
    reader
  end

  it 'reads raw streams by declared Length without trimming valid trailing newlines' do
    payload = "line one\n"
    object = +"10 0 obj\n<</Length #{payload.bytesize}>>\nstream\n"
    object << payload
    object << "\nendstream\nendobj\n"
    reader = build_reader(object, { 10 => 0 })

    result = reader.read_stream(10)

    expect(result).to eq(payload)
  end

  it 'resolves indirect Length references when reading stream bytes' do
    payload = 'hello-world'

    stream_object = +"10 0 obj\n<</Length 11 0 R>>\nstream\n"
    stream_object << payload
    stream_object << "\nendstream\nendobj\n"
    length_offset = stream_object.bytesize
    length_object = "11 0 obj\n#{payload.bytesize}\nendobj\n"
    data = stream_object + length_object

    reader = build_reader(data, { 10 => 0, 11 => length_offset })
    result = reader.read_stream(10)

    expect(result).to eq(payload)
  end
end
