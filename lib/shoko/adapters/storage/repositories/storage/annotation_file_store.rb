# frozen_string_literal: true

require 'time'
require 'securerandom'
require_relative '../../../../shared/text_sanitizer'
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
            rescue StandardError
              {}
            end

            def get(path)
              sanitize_list(load_all[path.to_s] || []).dup
            rescue StandardError
              []
            end

            def add(path, text, note, range, chapter_index, page_meta = nil)
              data = load_all
              key = path.to_s
              list = data[key] || []
              now = Time.now
              ann = {
                'id' => SecureRandom.uuid,
                'text' => sanitize_body(text),
                'note' => sanitize_body(note),
                'range' => range,
                'chapter_index' => chapter_index,
                'created_at' => now.iso8601,
              }
              if page_meta.is_a?(Hash)
                ann['page_current'] = page_meta[:current] || page_meta['current']
                ann['page_total'] = page_meta[:total] || page_meta['total']
                ann['page_mode'] = page_meta[:type] || page_meta['type']
              end
              list << ann
              data[key] = list
              save_all(data)
              true
            rescue StandardError
              false
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
              true
            rescue StandardError
              false
            end

            def delete(path, id)
              data = load_all
              key = path.to_s
              list = data[key] || []
              list.reject! { |a| a['id'] == id }
              list.empty? ? data.delete(key) : data[key] = list
              save_all(data)
              true
            rescue StandardError
              false
            end

            private

            def sanitize_all(data)
              return {} unless data.is_a?(Hash)

              data.transform_values { |list| sanitize_list(list) }
            end

            def sanitize_list(list)
              Array(list).map do |ann|
                next ann unless ann.is_a?(Hash)

                safe = ann.dup
                safe['text'] = sanitize_body(safe['text'])
                safe['note'] = sanitize_body(safe['note'])
                safe
              end
            end

            def sanitize_body(text)
              Shoko::Shared::TextSanitizer.sanitize(text.to_s, preserve_newlines: true,
                                                               preserve_tabs: true)
            end
          end
        end
      end
    end
  end
end
