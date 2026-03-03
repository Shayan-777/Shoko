# frozen_string_literal: true

require_relative '../xml_text_normalizer'

module Shoko
  module Core
    module BookFormats
      module Epub
        # Reads OPF and related XML entries from a zip or filesystem path.
        class OPFEntryReader
          def initialize(opf_path, zip: nil)
            @opf_path = opf_path
            @opf_dir = dirname(opf_path)
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
          rescue Shoko::Error
            raise
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

          def dirname(path)
            str = path.to_s
            idx = str.rindex('/')
            idx ? str[0...idx] : ''
          end

          def normalize_joined_path(base_dir, href)
            raw = if href.to_s.start_with?('/')
                    href.to_s.delete_prefix('/')
                  elsif base_dir.to_s.empty?
                    href.to_s
                  else
                    "#{base_dir}/#{href}"
                  end

            parts = []
            raw.split('/').each do |segment|
              next if segment.empty? || segment == '.'

              if segment == '..'
                parts.pop
              else
                parts << segment
              end
            end
            parts.join('/')
          end

          def relative_path(from, to)
            from_parts = normalize_joined_path('', from).split('/').reject(&:empty?)
            to_parts = normalize_joined_path('', to).split('/').reject(&:empty?)

            common = 0
            while common < from_parts.length && common < to_parts.length && from_parts[common] == to_parts[common]
              common += 1
            end

            up = Array.new(from_parts.length - common, '..')
            down = to_parts[common..] || []
            result = (up + down).join('/')
            result.empty? ? '.' : result
          end
        end
      end
    end
  end
end
