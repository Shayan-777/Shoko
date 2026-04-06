# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../../../shared/terminal/ansi'

module Shoko
  module Adapters
    module Ui
      module Components
        class TranslationPopupComponent < BaseComponent
          module TranslationPopup
            # Color, presentation, and formatting helpers for the translation popup.
            module PresentationSupport
              private

              def panel_bg
                translation_palette[:panel_bg]
              end

              def header_fg
                translation_palette[:header_fg]
              end

              def muted_fg
                translation_palette[:muted_fg]
              end

              def body_fg
                translation_palette[:body_fg]
              end

              def error_fg
                translation_palette[:error_fg]
              end

              def language_code(code)
                value = code.to_s.strip
                value.empty? ? 'auto' : value
              end

              def normalize_color_mode(mode)
                mode.to_s == 'light' ? :light : :dark
              end

              def translation_palette
                Adapters::Ui::Constants::ComponentPalettes.fetch(:translation_popup, @color_mode)
              end

              def reset
                Shoko::Shared::Terminal::Ansi::RESET
              end
            end
          end
        end
      end
    end
  end
end
