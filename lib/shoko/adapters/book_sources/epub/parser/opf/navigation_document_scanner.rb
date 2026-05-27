# frozen_string_literal: true

require_relative '../html_processor'
require_relative '../rexml_safe_parser'
require_relative 'element_name_helpers'

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Scans document content for anchor and heading labels.
        class OPFNavigationDocumentScanner
          include OPFElementNameHelpers

          # Value object for extracted anchor and heading labels.
          ScanResult = Struct.new(:anchors, :headings)
          private_constant :ScanResult
          HEADING_TAGS = %w[h1 h2 h3 h4 h5 h6].freeze
          ID_ATTRIBUTES = ['id', 'name', 'xml:id'].freeze
          XML_ENTITY_NAMES = %w[amp apos gt lt quot].freeze
          XML_DECLARATION_PATTERN = /\A\s*<\?xml[^>]*\?>/i
          DOCTYPE_PATTERN = /<!DOCTYPE[^>]*(?:\[[\s\S]*?\]\s*)?>/i
          DOCUMENT_FRAGMENT_ROOT = 'shoko-navigation-fragment'
          private_constant :HEADING_TAGS,
                           :ID_ATTRIBUTES,
                           :XML_ENTITY_NAMES,
                           :XML_DECLARATION_PATTERN,
                           :DOCTYPE_PATTERN,
                           :DOCUMENT_FRAGMENT_ROOT

          def initialize(cleaner:)
            @cleaner = cleaner
          end

          def scan(content)
            return ScanResult.new(anchors: {}, headings: []) unless content

            result = ScanResult.new(anchors: {}, headings: [])
            each_heading(content) do |heading|
              label = clean_label(heading.to_s)
              next if label.empty?

              heading_ids(heading).each { |anchor| result.anchors[anchor] = label }
              result.headings << label
            end
            result
          end

          private

          def each_heading(content)
            document = parse_navigation_document(content)
            return unless document&.root

            each_element_including_root(document.root) do |element|
              yield element if element_name?(element, *HEADING_TAGS)
            end
          end

          def heading_ids(heading)
            each_element_including_root(heading).each_with_object([]) do |element, ids|
              ids.concat(attribute_values(element, *ID_ATTRIBUTES))
            end.map(&:to_s).map(&:strip).reject(&:empty?).uniq
          end

          def parse_navigation_document(content)
            normalized = normalize_named_entities(content.to_s)
            parse_xml(normalized) || parse_wrapped_fragment(normalized)
          end

          # Parse-utility contract: returns the parsed document or nil
          # when REXML rejects the input. The nil is the signal that
          # tells `parse_navigation_document` to try the wrapped-fragment
          # fallback; without it the alternative parsing strategy can't
          # run. Exempt from `no_rescue_literal_default` for this reason
          # — see `EXEMPT_OFFENDERS` in the spec.
          def parse_xml(xml)
            REXMLSafeParser.parse(xml)
          rescue REXML::ParseException
            nil
          end

          def parse_wrapped_fragment(content)
            fragment = content
                       .sub(XML_DECLARATION_PATTERN, '')
                       .gsub(DOCTYPE_PATTERN, '')
            parse_xml("<#{DOCUMENT_FRAGMENT_ROOT}>#{fragment}</#{DOCUMENT_FRAGMENT_ROOT}>")
          end

          def normalize_named_entities(content)
            content.gsub(/&([A-Za-z][A-Za-z0-9]+);/) do |match|
              name = Regexp.last_match(1).downcase
              XML_ENTITY_NAMES.include?(name) ? match : decoded_entity(match)
            end
          end

          def decoded_entity(entity)
            decoded = HTMLProcessor.decode_entities(entity)
            decoded == entity ? ' ' : decoded
          end

          def clean_label(text)
            @cleaner.clean_label(text).to_s
          end
        end
      end
    end
  end
end
