# frozen_string_literal: true

require 'time'
require 'securerandom'
require_relative '../../../../shared/text_sanitizer'
require_relative '../../../../shared/hash_normalizer'
require_relative '../../../../core/models/annotation_draft'
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

            def add(path, text_or_draft, *legacy_args)
              data = load_all
              key = path.to_s
              list = data[key] || []
              ann = build_annotation_record(coerce_draft(text_or_draft, legacy_args))
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
                safe
              end
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
                'range' => annotation.range,
                'chapter_index' => annotation.chapter_index,
                'created_at' => now,
              }.merge(page_metadata_fields(annotation.page_meta))
            end

            def coerce_draft(text_or_draft, legacy_args)
              return text_or_draft if text_or_draft.is_a?(Shoko::Core::Models::AnnotationDraft) && legacy_args.empty?

              note, range, chapter_index, page_meta = legacy_args
              Shoko::Core::Models::AnnotationDraft.new(
                text: text_or_draft,
                note: note,
                range: range,
                chapter_index: chapter_index,
                page_meta: page_meta
              )
            end

            def page_metadata_fields(page_meta)
              return {} unless page_meta.is_a?(Hash)

              normalized_meta = Shoko::Shared::HashNormalizer.symbolize_keys(page_meta) || {}
              {
                'page_current' => normalized_meta[:current],
                'page_total' => normalized_meta[:total],
                'page_mode' => normalized_meta[:type],
              }
            end
          end
        end
      end
    end
  end
end
