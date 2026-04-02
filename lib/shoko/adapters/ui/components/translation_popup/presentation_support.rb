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
                return PANEL_BG_LIGHT if @color_mode == :light

                Adapters::Ui::Constants::Ui::TOOLTIP_BG_DEFAULT
              end

              def header_fg
                @color_mode == :light ? HEADER_FG_LIGHT : HEADER_FG_DARK
              end

              def muted_fg
                @color_mode == :light ? MUTED_FG_LIGHT : MUTED_FG_DARK
              end

              def body_fg
                return PANEL_FG_LIGHT if @color_mode == :light

                Adapters::Ui::Constants::Ui::COLOR_TEXT_PRIMARY
              end

              def error_fg
                @color_mode == :light ? ERROR_FG_LIGHT : ERROR_FG_DARK
              end

              def language_code(code)
                value = code.to_s.strip
                value.empty? ? 'auto' : value
              end

              def normalize_color_mode(mode)
                mode.to_s == 'light' ? :light : :dark
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
