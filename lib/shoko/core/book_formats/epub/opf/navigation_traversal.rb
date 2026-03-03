# frozen_string_literal: true

require 'rexml/document'

require_relative 'navigation_context'
require_relative '../rexml_safe_parser'
require_relative 'navigation_walker'
require_relative 'navigation_result'

module Shoko
  module Core
    module BookFormats
      module Epub
        # Parses nav/NCX documents and builds navigation entries with fallback labels.
        class OPFNavigationTraversal
          NAV_TYPE_ATTRIBUTES = %w[epub:type type role].freeze
          NAV_TOC_TYPES = %w[toc doc-toc].freeze

          def initialize(entry_reader:)
            @entry_reader = entry_reader
            @result_class = OPFNavigationResult
            @type_attributes = NAV_TYPE_ATTRIBUTES
            @toc_types = NAV_TOC_TYPES
          end

          def from_nav_path(path)
            list = nav_list_from_path(path)
            return empty_result unless list

            context = build_context(path)
            OPFNavigationWalker.new(context).walk_nav_list(list)
            context.to_result(@result_class)
          end

          def from_ncx_path(path)
            nav_map = nav_map_from_path(path)
            return empty_result unless nav_map

            context = build_context(path)
            OPFNavigationWalker.new(context).walk_nav_points(nav_map)
            context.to_result(@result_class)
          end

          private

          def empty_result
            @result_class.new(toc_entries: [], titles: {})
          end

          def build_context(source_path)
            OPFNavigationContext.root(source_path: source_path, entry_reader: @entry_reader)
          end

          def find_nav_toc_node(doc)
            doc.elements.each('//*[local-name()="nav"]') do |nav|
              return nav if nav_toc_type?(nav_type_value(nav))
            end

            nil
          end

          def nav_toc_type?(value)
            return false unless value

            @toc_types.include?(value.to_s.strip.downcase)
          end

          def nav_type_value(nav)
            attributes = nav.attributes
            attribute = attributes.enum_for(:each_attribute).find do |attr|
              type_attribute?(attr.expanded_name) || type_attribute?(attr.name)
            end
            attribute&.value
          end

          def type_attribute?(name)
            @type_attributes.include?(name)
          end

          def nav_list_from_path(path)
            content = @entry_reader.safe_read_entry(path)
            return nil unless content

            doc = REXMLSafeParser.parse(content)
            nav_list_from_document(doc)
          rescue REXML::ParseException
            nil
          end

          def nav_list_from_document(doc)
            nav = find_nav_toc_node(doc)
            return nil unless nav

            nav.elements['(.//*[local-name()="ol"] | .//*[local-name()="ul"])[1]']
          end

          def nav_map_from_path(path)
            ncx_content = @entry_reader.read_entry(path)
            ncx = REXMLSafeParser.parse(ncx_content)
            ncx.elements['//navMap']
          rescue Shoko::Error
            nil
          end
        end
      end
    end
  end
end
