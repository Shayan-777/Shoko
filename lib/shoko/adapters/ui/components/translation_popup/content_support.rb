# frozen_string_literal: true

require_relative '../base_component'

module Shoko
  module Adapters
    module Ui
      module Components
        class TranslationPopupComponent < BaseComponent
          module TranslationPopup
            # Content assembly and caching helpers for the translation popup.
            module ContentSupport
              private

              def metadata_line(width)
                info = []
                info << "Detected: #{language_code(result&.detected_source_lang || result&.source_lang)}"
                info << "Target: #{language_code(result&.target_lang)}"
                "#{muted_fg}#{pad_right(info.join('   '), width)}#{reset}"
              end

              def content_lines(width)
                @content_lines_cache[content_cache_key(width)] ||= build_content_lines(width)
              end

              def clear_content_cache!
                @content_lines_cache.clear
              end

              def build_content_lines(width)
                [
                  section_header('Original', width),
                  *body_lines(result&.query.to_s, width),
                  blank_line(width),
                  section_header(translated_section_label, width),
                  *body_lines(translated_section_text, width, error: translation_error?),
                ]
              end

              def content_cache_key(width)
                [result&.object_id, width, @color_mode]
              end

              def translated_section_label
                translation_error? ? 'Error' : 'Translated'
              end

              def translated_section_text
                return result&.error_message.to_s if translation_error?

                result&.translated_text.to_s
              end

              def translation_error?
                result&.error? == true
              end

              def section_header(label, width)
                "#{header_fg}#{pad_right(label, width)}#{reset}"
              end

              def body_lines(text, width, error: false)
                color = error ? error_fg : body_fg
                wrap_text(text.to_s, width).map do |line|
                  "#{color}#{pad_right(line, width)}#{reset}"
                end
              end

              def footer_text(width)
                hint = max_scroll_offset.positive? ? 'UP/DOWN scroll  ESC close' : 'ESC close'
                "#{muted_fg}#{pad_right(hint, width)}#{reset}"
              end

              def max_scroll_offset
                [content_lines(@last_content_width).length - @last_visible_body_lines, 0].max
              end

              def blank_line(width)
                ' ' * width
              end
            end
          end
        end
      end
    end
  end
end
