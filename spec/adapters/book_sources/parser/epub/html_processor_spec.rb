# frozen_string_literal: true

require 'spec_helper'
require 'shoko/adapters/book_sources/epub/parser/html_processor'

RSpec.describe Shoko::Adapters::BookSources::Epub::HTMLProcessor do
  describe '.clean_html' do
    it 'strips inline tags and decodes entities for display labels' do
      html = '<a id="toc"><span class="label">7&nbsp;&amp;&nbsp;8</span></a>'

      expect(described_class.clean_html(html)).to eq('7 & 8')
    end

    it 'collapses block and inline whitespace into a single-line label' do
      html = "<span>Chapter</span>\n<br/> <em>One</em>"

      expect(described_class.clean_html(html)).to eq('Chapter One')
    end
  end

  describe '.extract_title' do
    it 'extracts titles that contain nested markup' do
      html = '<html><body><h1><a id="chapter"><span>Nested Title</span></a></h1></body></html>'

      expect(described_class.extract_title(html)).to eq('Nested Title')
    end
  end
end
