# frozen_string_literal: true

require 'cgi'

module Shoko
  module Core
    module BookFormats
      module Epub
        # Locates nav and NCX sources referenced by an OPF manifest.
        class OPFNavigationSourceLocator
          NAV_PROPERTY = 'nav'
          NCX_EXTENSION = '.ncx'
          NCX_MEDIA_HINT = 'ncx'

          def initialize(opf:, entry_reader:)
            @opf = opf
            @entry_reader = entry_reader
            @decoder = CGI
          end

          def nav_path
            @opf.elements.each('//manifest/item') do |item|
              nav_path = nav_item_path(item)
              return nav_path if nav_path
            end

            nil
          end

          def ncx_path(manifest)
            spine_path = ncx_path_from_spine(manifest)
            return spine_path if spine_path

            candidate_ncx_paths.each do |candidate|
              return candidate if candidate && @entry_reader.entry_exists?(candidate)
            end

            nil
          end

          private

          def nav_item_path(item)
            properties_attr, href_attr = item.attributes.values_at('properties', 'href')
            properties = properties_attr&.value.to_s.split
            return nil unless properties.include?(NAV_PROPERTY)

            entry_path_for(href_attr&.value)
          end

          def ncx_path_from_spine(manifest)
            ncx_id = @opf.elements['//spine']&.attributes&.[]('toc')
            return nil unless ncx_id

            ncx_href = manifest[ncx_id]
            entry_path_for(ncx_href)
          end

          def candidate_ncx_paths
            @opf.elements.each_with_object([]) do |item, paths|
              candidate_path = ncx_candidate_path(item)
              paths << candidate_path if candidate_path
            end
          end

          def ncx_candidate_path(item)
            href_attr, media_attr = item.attributes.values_at('href', 'media-type')
            decoded = decoded_href(href_attr&.value)
            media_type = media_attr&.value.to_s.downcase
            return @entry_reader.join_path(decoded) if decoded &&
                                                       (media_type.include?(NCX_MEDIA_HINT) ||
                                                        decoded.downcase.end_with?(NCX_EXTENSION))

            nil
          end

          def decoded_href(href)
            href_string = href.to_s
            return nil if href_string.empty?

            @decoder.unescape(href_string)
          end

          def entry_path_for(href)
            decoded = decoded_href(href)
            return nil unless decoded

            path = @entry_reader.join_path(decoded)
            return nil unless path && @entry_reader.entry_exists?(path)

            path
          end
        end
      end
    end
  end
end
