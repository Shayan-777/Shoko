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
            # v1 anchored annotations to screen geometry (a per-frame +range+ and,
            # for page notes, +page_offset+); v2 anchors them to a layout-
            # independent, quote-based DocumentAnchor.
            SCHEMA_VERSION = 2

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

              ann = build_annotation_record(draft)
              with_update_lock do
                data = load_all_for_update
                key = path.to_s
                (data[key] ||= []) << ann
                save_all(data)
              end
              ann
            end

            def update(path, id, note)
              with_update_lock do
                data = load_all_for_update
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
            end

            def delete(path, id)
              with_update_lock do
                data = load_all_for_update
                key = path.to_s
                list = data[key] || []
                removed = list.find { |a| a['id'] == id }
                return nil unless removed

                list.reject! { |a| a['id'] == id }
                list.empty? ? data.delete(key) : data[key] = list
                save_all(data)
                removed
              end
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

            # Upgrade v1 (screen-geometry) records to v2 (document anchor) at
            # load time. Runs on the raw, string-keyed payload so the upgrade
            # flows through both reads and the read-modify-write of add/update/
            # delete; the next save then persists the v2 shape and the migration
            # stops running for that file.
            def migrate_entries(entries, from_version)
              return entries if from_version >= SCHEMA_VERSION

              entries.transform_values do |list|
                Array(list).map { |record| migrate_legacy_anchor(record) }
              end
            end

            # Re-home a legacy record onto a quote-based DocumentAnchor and drop
            # the dead screen-geometry fields. Idempotent: a record that already
            # carries an anchor is returned unchanged.
            def migrate_legacy_anchor(record)
              return record unless record.is_a?(Hash)
              return record if record.key?('anchor')

              quote = record['text'].to_s
              migrated = record.dup
              migrated['anchor'] = quote.empty? ? {} : { 'quote' => quote }
              %w[range page_current page_total page_mode page_offset].each { |field| migrated.delete(field) }
              migrated
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
