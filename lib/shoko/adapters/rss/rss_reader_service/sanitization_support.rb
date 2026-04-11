# frozen_string_literal: true

require 'time'

module Shoko
  module Adapters
    module Rss
      # Shared text and time normalization helpers for RSS reader records.
      module RssReaderServiceSanitizationSupport
        private

        def sanitize_text(text, preserve_newlines: false, max_length: nil)
          sanitized = if @text_sanitizer
                        @text_sanitizer.sanitize(
                          text.to_s,
                          preserve_newlines: preserve_newlines,
                          max_length: max_length
                        )
                      else
                        sanitize_text_default(text, preserve_newlines: preserve_newlines, max_length: max_length)
                      end
          value = sanitized.to_s.strip
          return nil if value.empty?

          value
        end

        def sanitize_text_default(text, preserve_newlines:, max_length:)
          value = Shoko::Shared::TextSanitizer.sanitize(
            text.to_s,
            preserve_newlines: preserve_newlines,
            preserve_tabs: false
          )
          max_length ? value[0, max_length] : value
        end

        def sanitize_time(value)
          parsed_time(value)&.utc&.iso8601
        end

        def time_to_epoch(value)
          parsed_time(value)&.to_i
        end

        def published_label(value)
          parsed = parsed_time(value)
          return 'Unknown date' unless parsed

          parsed.localtime.strftime('%Y-%m-%d %H:%M')
        end

        def normalize_scope(scope)
          case scope&.to_sym
          when :unread then :unread
          when :starred then :starred
          else :all
          end
        end

        def timestamp
          @wall_clock.utc_now.iso8601
        end

        def excerpt_from(text)
          excerpt = text.to_s.strip.gsub(/\s+/, ' ')[0, 320].to_s.strip
          return nil if excerpt.empty?

          excerpt
        end

        def parsed_time(value)
          text = value.to_s.strip
          return nil if text.empty?

          Time.parse(text)
        rescue ArgumentError
          invalid_parsed_time
        end

        def invalid_parsed_time
          nil
        end
      end
    end
  end
end
