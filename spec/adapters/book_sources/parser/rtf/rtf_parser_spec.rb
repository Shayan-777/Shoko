# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::Rtf::RtfParser do
  describe '#parse' do
    it 'parses minimal RTF document' do
      rtf = '{\rtf1 Hello world}'
      doc = described_class.new(rtf).parse

      expect(doc).to be_a(described_class::DocumentModel)
      text = doc.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include('Hello world')
    end

    it 'handles bold formatting' do
      rtf = '{\rtf1 normal {\b bold text} normal}'
      doc = described_class.new(rtf).parse

      runs = doc.paragraphs.flat_map(&:runs)
      bold_runs = runs.select(&:bold)
      expect(bold_runs).not_to be_empty
      expect(bold_runs.first.text).to include('bold text')
    end

    it 'turns bold off with \b0' do
      rtf = '{\rtf1 {\b bold\b0  not bold}}'
      doc = described_class.new(rtf).parse

      runs = doc.paragraphs.flat_map(&:runs)
      non_bold = runs.reject(&:bold)
      expect(non_bold.map(&:text).join).to include('not bold')
    end

    it 'handles italic formatting' do
      rtf = '{\rtf1 {\i italic text}}'
      doc = described_class.new(rtf).parse

      runs = doc.paragraphs.flat_map(&:runs)
      italic_runs = runs.select(&:italic)
      expect(italic_runs).not_to be_empty
      expect(italic_runs.first.text).to include('italic')
    end

    it 'handles nested bold and italic' do
      rtf = '{\rtf1 {\b\i bold italic}}'
      doc = described_class.new(rtf).parse

      run = doc.paragraphs.flat_map(&:runs).first
      expect(run.bold).to be true
      expect(run.italic).to be true
    end

    it 'handles underline formatting' do
      rtf = '{\rtf1 {\ul underlined}}'
      doc = described_class.new(rtf).parse

      run = doc.paragraphs.flat_map(&:runs).first
      expect(run.underline).to be true
    end

    it 'handles strikethrough formatting' do
      rtf = '{\rtf1 {\strike struck}}'
      doc = described_class.new(rtf).parse

      run = doc.paragraphs.flat_map(&:runs).first
      expect(run.strikethrough).to be true
    end

    it 'handles superscript and subscript' do
      rtf = '{\rtf1 x{\super 2} + y{\sub 3}}'
      doc = described_class.new(rtf).parse

      runs = doc.paragraphs.flat_map(&:runs)
      sup = runs.find(&:superscript)
      sub = runs.find(&:subscript)
      expect(sup).not_to be_nil
      expect(sub).not_to be_nil
    end

    it 'handles paragraph breaks' do
      rtf = '{\rtf1 First paragraph.\par Second paragraph.}'
      doc = described_class.new(rtf).parse

      expect(doc.paragraphs.length).to eq(2)
      expect(doc.paragraphs[0].runs.first.text).to include('First')
      expect(doc.paragraphs[1].runs.first.text).to include('Second')
    end

    it 'handles emdash named character' do
      rtf = '{\rtf1 word\emdash word}'
      doc = described_class.new(rtf).parse

      text = doc.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include("\u2014")
    end

    it 'handles endash named character' do
      rtf = '{\rtf1 1\endash 10}'
      doc = described_class.new(rtf).parse

      text = doc.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include("\u2013")
    end

    it 'handles smart quotes' do
      rtf = '{\rtf1 \ldblquote Hello\rdblquote }'
      doc = described_class.new(rtf).parse

      text = doc.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include("\u201C")
      expect(text).to include("\u201D")
    end

    it 'handles hex escapes with CP1252' do
      rtf = "{\rtf1\\ansicpg1252 caf\\'e9}"
      doc = described_class.new(rtf).parse

      text = doc.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include("\u00E9") # e with acute
    end

    it 'handles Unicode escapes' do
      rtf = '{\rtf1 \u8212? is emdash}'
      doc = described_class.new(rtf).parse

      text = doc.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include("\u2014")
      expect(text).not_to include('?') # fallback char should be skipped
    end

    it 'skips malformed Unicode escape values without crashing' do
      rtf = '{\rtf1 valid \u9999999? text}'

      expect { described_class.new(rtf).parse }.not_to raise_error
      text = described_class.new(rtf).parse.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include('valid')
      expect(text).to include('text')
    end

    it 'skips malformed hex escapes without crashing' do
      rtf = "{\\rtf1 bad\\'zzhex}"

      expect { described_class.new(rtf).parse }.not_to raise_error
      text = described_class.new(rtf).parse.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include('bad')
      expect(text).to include('hex')
    end

    it 'handles negative Unicode values' do
      # \u-257 => 65536 - 257 = 65279 => U+FEFF (BOM)
      rtf = '{\rtf1 \u-257?text}'
      doc = described_class.new(rtf).parse

      text = doc.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include('text')
    end

    it 'parses font table' do
      rtf = '{\rtf1{\fonttbl{\f0 Times New Roman;}{\f1 Arial;}}Hello}'
      doc = described_class.new(rtf).parse

      expect(doc.fonts[0]).to eq('Times New Roman')
      expect(doc.fonts[1]).to eq('Arial')
    end

    it 'parses color table' do
      # First ; after \colortbl is the auto/default color entry
      rtf = '{\rtf1{\colortbl;\red255\green0\blue0;\red0\green128\blue255;}text}'
      doc = described_class.new(rtf).parse

      expect(doc.colors.length).to eq(3)
      expect(doc.colors[0]).to eq([0, 0, 0])       # auto color
      expect(doc.colors[1]).to eq([255, 0, 0])
      expect(doc.colors[2]).to eq([0, 128, 255])
    end

    it 'parses info block metadata' do
      rtf = '{\rtf1{\info{\title My Book}{\author John Doe}}Content}'
      doc = described_class.new(rtf).parse

      expect(doc.info.title).to eq('My Book')
      expect(doc.info.author).to eq('John Doe')
    end

    it 'parses info creation date' do
      rtf = '{\rtf1{\info{\creatim\yr2005\mo4\dy10\hr5\min27}}text}'
      doc = described_class.new(rtf).parse

      expect(doc.info.creatim).to eq('2005-04-10')
    end

    it 'handles center alignment' do
      rtf = '{\rtf1\qc Centered text}'
      doc = described_class.new(rtf).parse

      expect(doc.paragraphs.first.alignment).to eq(:center)
    end

    it 'handles justify alignment' do
      rtf = '{\rtf1\qj Justified text}'
      doc = described_class.new(rtf).parse

      expect(doc.paragraphs.first.alignment).to eq(:justify)
    end

    it 'handles font size' do
      rtf = '{\rtf1 {\fs72 Large text}}'
      doc = described_class.new(rtf).parse

      run = doc.paragraphs.flat_map(&:runs).first
      expect(run.font_size).to eq(72)
    end

    it 'handles \plain reset' do
      rtf = '{\rtf1 {\b\i bold italic\plain  normal}}'
      doc = described_class.new(rtf).parse

      runs = doc.paragraphs.flat_map(&:runs)
      normal_run = runs.find { |r| !r.bold && !r.italic }
      expect(normal_run).not_to be_nil
      expect(normal_run.text).to include('normal')
    end

    it 'handles \pard paragraph reset' do
      rtf = '{\rtf1\qc centered\par\pard\qj justified}'
      doc = described_class.new(rtf).parse

      expect(doc.paragraphs.first.alignment).to eq(:center)
      expect(doc.paragraphs.last.alignment).to eq(:justify)
    end

    it 'skips picture destinations' do
      rtf = '{\rtf1 Before{\pict 00ff00ff}After}'
      doc = described_class.new(rtf).parse

      text = doc.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include('Before')
      expect(text).to include('After')
      expect(text).not_to include('00ff')
    end

    it 'skips ignorable destinations with \*' do
      rtf = '{\rtf1 Before{\*\unknowndest some data}After}'
      doc = described_class.new(rtf).parse

      text = doc.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include('Before')
      expect(text).to include('After')
      expect(text).not_to include('some data')
    end

    it 'handles page break markers' do
      rtf = '{\rtf1 Page one.\page Page two.}'
      doc = described_class.new(rtf).parse

      page_two_paras = doc.paragraphs.select(&:page_break_before)
      expect(page_two_paras).not_to be_empty
    end

    it 'handles empty input gracefully' do
      doc = described_class.new('').parse

      expect(doc.paragraphs).to be_empty
      expect(doc.fonts).to be_empty
      expect(doc.colors).to be_empty
    end

    it 'handles literal braces' do
      rtf = '{\rtf1 opening \{ and closing \}}'
      doc = described_class.new(rtf).parse

      text = doc.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include('{')
      expect(text).to include('}')
    end

    it 'handles literal backslash' do
      rtf = '{\rtf1 path\\\\to\\\\file}'
      doc = described_class.new(rtf).parse

      text = doc.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include('\\')
    end

    it 'handles non-breaking space' do
      rtf = '{\rtf1 hello\~world}'
      doc = described_class.new(rtf).parse

      text = doc.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include("\u00A0")
    end

    it 'handles tab characters' do
      rtf = '{\rtf1 before\tab after}'
      doc = described_class.new(rtf).parse

      text = doc.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include("\t")
    end

    it 'handles first line indent' do
      rtf = '{\rtf1\fi454 Indented text}'
      doc = described_class.new(rtf).parse

      expect(doc.paragraphs.first.first_indent).to eq(454)
    end

    it 'ignores unknown control words without dropping nearby content' do
      rtf = '{\rtf1 begin\foobar123 middle\par end}'
      doc = described_class.new(rtf).parse

      text = doc.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include('begin')
      expect(text).to include('middle')
      expect(text).to include('end')
    end

    it 'skips nested ignorable destinations completely' do
      rtf = '{\rtf1 Before{\*\unknown one {two} three}After}'
      doc = described_class.new(rtf).parse

      text = doc.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include('Before')
      expect(text).to include('After')
      expect(text).not_to include('one')
      expect(text).not_to include('two')
      expect(text).not_to include('three')
    end

    it 'skips known destinations with nested groups' do
      rtf = '{\rtf1 A{\header ignored {still ignored}}B}'
      doc = described_class.new(rtf).parse

      text = doc.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include('A')
      expect(text).to include('B')
      expect(text).not_to include('ignored')
    end

    it 'handles truncated hex escapes at end-of-input without raising' do
      rtf = "{\\rtf1 ok\\'F}"

      expect { described_class.new(rtf).parse }.not_to raise_error
      text = described_class.new(rtf).parse.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
      expect(text).to include('ok')
    end

    context 'with real RTF file', :requires_book_fixtures do
      let(:path) { book_fixture_path('Pride And Prejudice (Austen Jane).rtf') }

      it 'parses the full document' do
        raw = File.binread(path).force_encoding('BINARY').encode('UTF-8',
          invalid: :replace, undef: :replace, replace: '')
        doc = described_class.new(raw).parse

        expect(doc.paragraphs.length).to be > 100
      end

      it 'extracts font table' do
        raw = File.binread(path).force_encoding('BINARY').encode('UTF-8',
          invalid: :replace, undef: :replace, replace: '')
        doc = described_class.new(raw).parse

        expect(doc.fonts).not_to be_empty
        expect(doc.fonts[0]).to include('Times New Roman')
      end

      it 'extracts info metadata' do
        raw = File.binread(path).force_encoding('BINARY').encode('UTF-8',
          invalid: :replace, undef: :replace, replace: '')
        doc = described_class.new(raw).parse

        expect(doc.info.author).to eq('Braven')
      end

      it 'preserves emdash characters from source' do
        raw = File.binread(path).force_encoding('BINARY').encode('UTF-8',
          invalid: :replace, undef: :replace, replace: '')
        doc = described_class.new(raw).parse

        all_text = doc.paragraphs.flat_map { |p| p.runs.map(&:text) }.join
        expect(all_text).to include("\u2014")
      end

      it 'contains bold centered chapter headings' do
        raw = File.binread(path).force_encoding('BINARY').encode('UTF-8',
          invalid: :replace, undef: :replace, replace: '')
        doc = described_class.new(raw).parse

        chapter_paras = doc.paragraphs.select do |p|
          p.alignment == :center &&
            p.runs.all?(&:bold) &&
            p.runs.map(&:text).join.strip.match?(/\ACHAPTER\s+[IVXLCDM]+\z/)
        end
        expect(chapter_paras.length).to be >= 50
      end
    end
  end
end
