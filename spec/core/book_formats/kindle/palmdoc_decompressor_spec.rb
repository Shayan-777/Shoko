# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::BookFormats::Kindle::PalmdocDecompressor do
  describe '.decompress' do
    it 'passes through literal ASCII bytes unchanged' do
      # Bytes 0x09-0x7F are literal
      input = 'Hello World'.b
      expect(described_class.decompress(input)).to eq('Hello World')
    end

    it 'handles literal NUL bytes' do
      input = "\x00".b
      expect(described_class.decompress(input)).to eq("\x00")
    end

    it 'handles multi-byte literal copies (0x01-0x08)' do
      # 0x03 means copy next 3 bytes literally
      input = "\x03ABC".b
      expect(described_class.decompress(input)).to eq('ABC')
    end

    it 'handles space encoding (0xC0-0xFF)' do
      # 0xC0-0xFF: space + (byte XOR 0x80)
      # 0xF4 = space + (0xF4 ^ 0x80) = space + 0x74 = space + 't'
      input = "\xF4".b
      expect(described_class.decompress(input)).to eq(' t')
    end

    it 'decompresses LZ77 back-references correctly' do
      # Build input that creates a back-reference
      # First write "abcabc" where the second "abc" is a back-reference
      # to the first "abc" (distance=3, length=3)
      # For PalmDOC: byte pair where distance=3, length=3 (encoded as 0)
      # pair = (distance << 3) | (length - 3) = (3 << 3) | 0 = 24 = 0x18
      # high byte = 0x80 | (0x18 >> 8) = 0x80
      # low byte = 0x18 & 0xFF = 0x18
      input = "abc\x80\x18".b
      result = described_class.decompress(input)
      expect(result).to eq('abcabc')
    end

    it 'handles empty input' do
      expect(described_class.decompress('')).to eq('')
    end

    it 'decompresses real PalmDOC data correctly' do
      # Simple test: compress "the the the" style patterns
      # "the " followed by back-ref (distance=4, length=4) repeated
      input = "the \x80\x23".b  # distance=4, length=3+3=6? Let me calculate:
      # pair = 0x8023; distance = (0x8023 >> 3) & 0x7FF = 0x004 = 4; length = (0x8023 & 7) + 3 = 3 + 3 = 6
      result = described_class.decompress(input)
      # Should copy 6 bytes from 4 positions back in output (output = "the ")
      # Position: output[-4] = 't', 'h', 'e', ' ', 't', 'h' → "the the th"
      expect(result).to eq("the the th")
    end
  end

  describe '.strip_trailing_data' do
    it 'returns data unchanged when flags are zero' do
      data = 'hello world'.b
      expect(described_class.strip_trailing_data(data, 0)).to eq(data)
    end

    it 'strips multibyte overlap when bit 0 is set' do
      # Bit 0 set: last byte & 0x03 = overlap count, strip overlap + 1 bytes
      # Last byte = 0x01 → overlap = 1, strip 2 bytes
      data = "hello\x00\x01".b
      result = described_class.strip_trailing_data(data, 1)
      expect(result).to eq('hello')
    end

    it 'strips trailing entries when flags >> 1 > 0' do
      # flags = 2 → trailing_count = 1, multibyte = 0
      # Trailing entry: backward variable-length int with 0x80 stop bit
      # Size = 2 (encoded as 0x82 = 0x80 | 2)
      data = "hello\x82\x82".b  # last 2 bytes are trailing entry
      result = described_class.strip_trailing_data(data, 2)
      expect(result).to eq('hello')
    end
  end

  context 'integration with real files' do
    let(:base_dir) { File.join(File.dirname(__FILE__), '../../../..') }

    it 'decompresses MOBI text records to expected length' do
      path = File.join(base_dir, 'Persuasion (Jane Austen).mobi')
      skip 'MOBI file not available' unless File.exist?(path)

      data = File.binread(path)
      pdb = Shoko::Core::BookFormats::Kindle::PdbHeaderParser.new(data)
      r0 = pdb.record_data(0)
      mobi = Shoko::Core::BookFormats::Kindle::MobiHeaderParser.new(r0)

      total = +''
      mobi.text_record_count.times do |i|
        rec = pdb.record_data(i + 1)
        rec = described_class.strip_trailing_data(rec, mobi.extra_data_flags)
        total << described_class.decompress(rec)
      end

      expect(total.bytesize).to eq(mobi.text_length)
    end
  end
end
