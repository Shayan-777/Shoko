# frozen_string_literal: true

require_relative 'path_resolution'
require_relative '../xml_text_normalizer'

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Reads OPF and related XML entries from a zip or filesystem path.
        class OPFEntryReader
          def initialize(opf_path, zip: nil)
            @opf_path = opf_path
            @opf_dir = OPFPathResolution.dirname(opf_path)
            @zip = zip
          end

          def zip?
            !@zip.nil?
          end

          def read_raw(path)
            return @zip.read(path) if zip?

            raise ArgumentError, 'OPFEntryReader requires a zip-backed source'
          end

          def read_entry(path)
            normalize_xml_text(read_raw(path))
          end

          def safe_read_entry(path)
            read_entry(path)
          end

          def entry_exists?(path)
            return !!@zip.find_entry(path) if zip?

            false
          end

          def join_path(href)
            expand_path(@opf_dir, href)
          end

          def expand_path(base_dir, href)
            return nil if href.nil? || href.to_s.empty?

            normalize_joined_path(base_dir, href)
          end

          def normalize_opf_relative_href(href)
            return nil if href.nil? || href.to_s.empty?

            joined = join_path(href)
            return nil unless joined

            relative_path(@opf_dir, joined)
          end

          def opf_relative_path(path)
            return nil if path.nil? || path.to_s.empty?

            relative_path(@opf_dir, path)
          end

          def normalize_xml_text(content)
            XmlTextNormalizer.normalize(content)
          end

          private

          def normalize_joined_path(base_dir, href)
            path_source(base_dir, href).split('/').each_with_object([]) do |segment, parts|
              append_path_segment(parts, segment)
            end.join('/')
          end

          def relative_path(from, to)
            from_parts = normalized_path_parts(from)
            to_parts = normalized_path_parts(to)
            common = shared_prefix_length(from_parts, to_parts)
            up = Array.new(from_parts.length - common, '..')
            down = to_parts[common..] || []
            result = (up + down).join('/')
            result.empty? ? '.' : result
          end

          def path_source(base_dir, href)
            return href.to_s.delete_prefix('/') if href.to_s.start_with?('/')
            return href.to_s if base_dir.to_s.empty?

            "#{base_dir}/#{href}"
          end

          def append_path_segment(parts, segment)
            return if segment.empty? || segment == '.'

            segment == '..' ? parts.pop : parts << segment
          end

          def normalized_path_parts(path)
            normalize_joined_path('', path).split('/').reject(&:empty?)
          end

          def shared_prefix_length(from_parts, to_parts)
            common = 0
            while common < from_parts.length &&
                  common < to_parts.length &&
                  from_parts[common] == to_parts[common]
              common += 1
            end
            common
          end
        end
      end
    end
  end
end
