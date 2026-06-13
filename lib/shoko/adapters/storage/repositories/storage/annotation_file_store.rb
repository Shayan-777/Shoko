# frozen_string_literal: true

require 'time'
require 'securerandom'
require 'shoko/shared/text_sanitizer'
require 'shoko/shared/hash_normalizer'
require 'shoko/core/models/annotation_draft'
require_relative 'base_file_store'

module Shoko
  module Adapters
    module Storage
      module Repositories
        module Storage
          # File-backed annotation storage under Domain.
          # Persists annotations to ${XDG_CONFIG_HOME:-~/.config}/shoko/annotations.json
          class AnnotationFileStore < BaseFileStore
            FILE_NAME = 'annotations.json'

            def all
              sanitize_all(load_all)
            end

            def get(path)
              sanitize_list(load_all[path.to_s] || []).dup
            end

            def add(path, draft)
              unless draft.is_a?(Shoko::Core::Models::AnnotationDraft)
                raise ArgumentError, "draft must be #{Shoko::Core::Models::AnnotationDraft}"
              end

              data = load_all
              key = path.to_s
              list = data[key] || []
              ann = build_annotation_record(draft)
              list << ann
              data[key] = list
              save_all(data)
              ann
            end

            def update(path, id, note)
              data = load_all
              key = path.to_s
              list = data[key] || []
              ann = list.find { |a| a['id'] == id }
              return false unless ann

              ann['note'] = sanitize_body(note)
              ann['updated_at'] = Time.now.iso8601
              data[key] = list
              save_all(data)
              ann
            end

            def delete(path, id)
              data = load_all
              key = path.to_s
              list = data[key] || []
              removed = list.find { |a| a['id'] == id }
              return nil unless removed

              list.reject! { |a| a['id'] == id }
              list.empty? ? data.delete(key) : data[key] = list
              save_all(data)
              removed
            end

            private

            def sanitize_all(data)
              return {} unless data.is_a?(Hash)

              data.transform_values { |list| sanitize_list(list) }
            end

            def sanitize_list(list)
              Array(list).map do |ann|
                next ann unless ann.is_a?(Hash)

                safe = Shoko::Shared::HashNormalizer.deep_symbolize(ann)
                safe[:text] = sanitize_body(safe[:text])
                safe[:note] = sanitize_body(safe[:note])
                migrate_legacy_anchor!(safe)
                safe
              end
            end

            # Records written before document anchors carried a screen-geometry
            # +range+ (and, for page notes, a +page_offset+) that meant nothing
            # outside the frame they were captured in. Re-home them onto a
            # quote-based DocumentAnchor — layout-independent and re-locatable —
            # and drop the dead geometry fields. The next save persists the new
            # shape, so this runs at most once per record.
            def migrate_legacy_anchor!(record)
              return if record.key?(:anchor)

              quote = record[:text].to_s
              record[:anchor] = quote.empty? ? {} : { quote: quote }
              record.delete(:range)
              record.delete(:page_current)
              record.delete(:page_total)
              record.delete(:page_mode)
              record.delete(:page_offset)
            end

            def sanitize_body(text)
              Shoko::Shared::TextSanitizer.sanitize(text.to_s, preserve_newlines: true, preserve_tabs: true)
            end

            def build_annotation_record(annotation)
              now = Time.now.iso8601
              {
                'id' => SecureRandom.uuid,
                'text' => sanitize_body(annotation.text),
                'note' => sanitize_body(annotation.note),
                'anchor' => anchor_hash(annotation.anchor),
                'chapter_index' => annotation.chapter_index,
                'created_at' => now,
              }
            end

            def anchor_hash(anchor)
              return {} if anchor.nil?
              return anchor.to_h if anchor.respond_to?(:to_h)

              {}
            end
          end
        end
      end
    end
  end
end
