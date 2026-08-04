# frozen_string_literal: true

require 'cgi'
require 'rexml/document'

require 'shoko/adapters/support/rexml_safe_parser'
require_relative 'opf/entry_reader'
require_relative 'opf/metadata_extractor'
require_relative 'opf/navigation_extractor'

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Processes OPF files.
        class OPFProcessor
          # Value object describing a resolved spine item.
          SpineItem = Struct.new(:file_path, :number, :title, :href)
          private_constant :SpineItem

          attr_reader :toc_entries

          def initialize(opf_path, zip: nil, instrumentation: nil)
            @opf_path = opf_path
            @instrumentation = instrumentation
            @entry_reader = OPFEntryReader.new(opf_path, zip: zip)
            content = read_opf_content
            @opf = instrument('opf.parse') do
              Shoko::Adapters::Support::REXMLSafeParser.parse(content)
            end
            @toc_entries = []
            @navigation_extractor = OPFNavigationExtractor.new(opf: @opf, entry_reader: @entry_reader)
          end

          def extract_metadata
            OPFMetadataExtractor.new(@opf).extract
          end

          def build_manifest_map
            manifest = {}
            @opf.elements.each('//manifest/item') do |item|
              id, href = manifest_item_id_href(item)
              next unless id && href

              normalized = @entry_reader.normalize_opf_relative_href(CGI.unescape(href))
              manifest[id] = normalized if normalized
            end
            manifest
          end

          def extract_chapter_titles(manifest)
            result = @navigation_extractor.extract(manifest)
            @toc_entries = result.toc_entries
            result.titles
          end

          def process_spine(manifest, chapter_titles)
            chapter_num = 1
            @opf.elements.each('//spine/itemref') do |itemref|
              item = build_spine_item(itemref, chapter_num, manifest, chapter_titles)
              next unless item

              yield(item)
              chapter_num += 1
            end
          end

          private

          def read_opf_content
            raw = if @entry_reader.zip?
                    instrument('zip.read') do
                      @entry_reader.read_raw(@opf_path)
                    end
                  else
                    @entry_reader.read_raw(@opf_path)
                  end
            @entry_reader.normalize_xml_text(raw)
          end

          def instrument(label, &)
            if @instrumentation
              @instrumentation.measure(label, &)
            else
              yield
            end
          end

          def manifest_item_id_href(item)
            attrs = item.attributes
            [attrs['id'], attrs['href']]
          end

          def build_spine_item(itemref, number, manifest, chapter_titles)
            idref = itemref.attributes['idref']
            return nil unless idref

            href = manifest[idref]
            return nil unless href

            file_path = @entry_reader.join_path(href)
            return nil unless file_path && @entry_reader.entry_exists?(file_path)

            SpineItem.new(file_path: file_path, number: number, title: chapter_titles[href], href: href)
          end
        end
      end
    end
  end
end
