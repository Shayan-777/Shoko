# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Composition::RuntimeComposition do
  describe '.manifest_features' do
    it 'is deterministic without synthetic namespace preload entries' do
      features_a = described_class.manifest_features
      features_b = described_class.manifest_features

      expect(features_a).to eq(features_b)
      expect(features_a).not_to include('shoko/shared/namespaces')
    end

    it 'excludes runtime composition and test support files' do
      features = described_class.manifest_features

      expect(features).not_to include('shoko/composition/runtime_composition')
      expect(features.grep(/\Ashoko\/test_support\//)).to eq([])
    end

    it 'contains runtime format files needed by non-fixture specs' do
      features = described_class.manifest_features

      expect(features).to include(
        'shoko/adapters/book_sources/epub/parser/xhtml_content_parser',
        'shoko/adapters/book_sources/fb2/parser/fb2_content_parser',
        'shoko/adapters/book_sources/kindle/parser/pdb_header_parser',
        'shoko/adapters/book_sources/rtf/parser/rtf_parser',
        'shoko/adapters/book_sources/epub/epub_importer',
        'shoko/adapters/book_sources/fb2/fb2_importer',
        'shoko/adapters/book_sources/kindle/kindle_importer',
        'shoko/adapters/book_sources/rtf/rtf_importer'
      )
    end
  end

  describe '.boot!' do
    around do |example|
      prior_booted = described_class.instance_variable_get(:@booted)
      prior_manifest = described_class.instance_variable_get(:@manifest_features)
      begin
        described_class.instance_variable_set(:@booted, false)
        described_class.instance_variable_set(:@manifest_features, nil)
        example.run
      ensure
        described_class.instance_variable_set(:@booted, prior_booted)
        described_class.instance_variable_set(:@manifest_features, prior_manifest)
      end
    end

    it 'boots idempotently' do
      described_class.boot!
      expect(described_class.booted?).to eq(true)
      features_obj = described_class.manifest_features

      expect { described_class.boot! }.not_to raise_error
      expect(described_class.booted?).to eq(true)
      expect(described_class.manifest_features.object_id).to eq(features_obj.object_id)
    end

    it 'loads key format constants referenced by required non-fixture specs' do
      described_class.boot!

      expect(defined?(Shoko::Adapters::BookSources::Epub::XHTMLContentParser)).to eq('constant')
      expect(defined?(Shoko::Adapters::BookSources::Fb2::Fb2ContentParser)).to eq('constant')
      expect(defined?(Shoko::Adapters::BookSources::Kindle::PdbHeaderParser)).to eq('constant')
      expect(defined?(Shoko::Adapters::BookSources::Rtf::RtfParser)).to eq('constant')
      expect(defined?(Shoko::Adapters::BookSources::Epub::EpubImporter)).to eq('constant')
      expect(defined?(Shoko::Adapters::BookSources::Fb2::Fb2Importer)).to eq('constant')
      expect(defined?(Shoko::Adapters::BookSources::Kindle::KindleImporter)).to eq('constant')
      expect(defined?(Shoko::Adapters::BookSources::Rtf::RtfImporter)).to eq('constant')
    end
  end
end
