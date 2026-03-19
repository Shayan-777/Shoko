# frozen_string_literal: true

require 'cgi'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          module InlineLink
            # Resolves an inline-link href to a chapter and line offset.
            class DestinationResolver
              def initialize(reader_state_reader:, document_reader:, anchor_resolver:)
                @reader_state_reader = reader_state_reader
                @document_reader = document_reader
                @anchor_resolver = anchor_resolver
                @chapter_index_map_key = nil
                @chapter_index_map = {}
              end

              def destination_for(href, entry)
                chapter_index = target_chapter_index(href, entry)
                return nil unless chapter_index

                fragment = fragment_from_href(href)
                line_offset = if fragment
                                @anchor_resolver.line_offset_for_href(href: href, chapter_index: chapter_index)
                              else
                                0
                              end
                if line_offset.nil?
                  return nil if chapter_index == current_chapter_index && fragment

                  line_offset = 0
                end
                { chapter_index: chapter_index, line_offset: line_offset.to_i }
              end

              private

              def target_chapter_index(href, entry)
                current = current_chapter_index
                core = core_href(href)
                return current if core.nil? || core.empty?
                return nil if external_href?(core)

                base = chapter_source_path_from_entry(entry) || chapter_source_path_for(current)
                target_path = resolve_target_path(core, base)
                return nil unless target_path

                chapter_index_for_path(target_path) || (same_path?(target_path, base) ? current : nil)
              end

              def core_href(href)
                value = href.to_s.strip
                return nil if value.empty?

                CGI.unescape(value.split('#', 2).first.to_s).strip
              end

              def fragment_from_href(href)
                fragment = href.to_s.split('#', 2)[1]
                return nil if fragment.nil?

                decoded = CGI.unescape(fragment.to_s).strip
                decoded.empty? ? nil : decoded
              end

              def external_href?(href)
                value = href.to_s.strip
                return false if value.empty?

                value.start_with?('//') || value.match?(/\A[a-z][a-z0-9+.-]*:/i)
              end

              def resolve_target_path(core, base_source_path)
                raw = core.to_s.strip
                return nil if raw.empty?
                return normalize_path(raw) if raw.start_with?('/')

                base = normalize_path(base_source_path)
                return normalize_path(raw) if base.nil? || base.empty?

                base_dir = File.dirname(base)
                normalize_path(File.expand_path(File.join('/', base_dir, raw), '/'))
              end

              def chapter_source_path_from_entry(entry)
                normalize_path(value_for(entry, :chapter_source_path))
              end

              def chapter_source_path_for(index)
                chapter = document_chapter(index)
                return nil unless chapter

                metadata = chapter.metadata || {}
                normalize_path(metadata[:source_path] || metadata[:href])
              end

              def chapter_index_for_path(path)
                normalized = normalize_path(path)
                return nil unless normalized

                map = chapter_index_map
                map[normalized] || map[normalized.downcase]
              end

              def chapter_index_map
                doc = document
                return {} unless doc

                cache_key = doc.object_id
                if @chapter_index_map_key != cache_key
                  @chapter_index_map_key = cache_key
                  @chapter_index_map = build_chapter_index_map(doc)
                end
                @chapter_index_map
              end

              def build_chapter_index_map(doc)
                chapters_for_document(doc).each_with_index.with_object({}) do |(chapter, idx), map|
                  register_chapter_paths(map, chapter, idx)
                end
              end

              def chapters_for_document(doc)
                return Array(doc.chapters) if doc.respond_to?(:chapters)

                count = doc.respond_to?(:chapter_count) ? doc.chapter_count.to_i : 0
                Array.new(count) { |idx| doc.get_chapter(idx) }
              end

              def register_chapter_paths(map, chapter, idx)
                return unless chapter

                metadata = chapter.metadata || {}
                candidates = [
                  metadata[:source_path],
                  metadata[:href],
                ]
                candidates.each do |candidate|
                  normalized = normalize_path(candidate)
                  next unless normalized

                  map[normalized] ||= idx
                  map[normalized.downcase] ||= idx
                end
              end

              def same_path?(path_a, path_b)
                norm_a = normalize_path(path_a)
                norm_b = normalize_path(path_b)
                return false unless norm_a && norm_b

                norm_a == norm_b || norm_a.casecmp?(norm_b)
              end

              def normalize_path(path)
                value = CGI.unescape(path.to_s).strip
                return nil if value.empty?

                value = value.split(/[?#]/, 2).first.to_s
                value = value.sub(%r{\A/+}, '')
                value.empty? ? nil : value
              end

              def current_chapter_index
                @reader_state_reader.current_chapter.to_i
              end

              def document
                @document_reader.call
              end

              def document_chapter(index)
                doc = document
                return nil unless doc

                if doc.respond_to?(:chapters)
                  Array(doc.chapters)[index]
                else
                  doc.get_chapter(index)
                end
              end

              def value_for(source, key)
                return nil unless source.respond_to?(:[])

                normalized = source.to_h do |entry_key, value|
                  [entry_key.is_a?(String) ? entry_key.to_sym : entry_key, value]
                end
                normalized[key]
              end
            end
          end
        end
      end
    end
  end
end
