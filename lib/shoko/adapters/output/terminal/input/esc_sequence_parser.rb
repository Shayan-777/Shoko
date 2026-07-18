# frozen_string_literal: true

require_relative 'decoder_scanner'

module Shoko
  module Adapters
    module Output
      module Terminal
        class TerminalInput
          # Dispatches ESC-prefixed sequences to decoder actions.
          class EscSequenceParser
            HANDLERS = {
              0x1B => :escape,
              0x5B => :csi,
              0x4F => :ss3,
              0x5D => :osc,
              0x50 => :string,
              0x58 => :string,
              0x5E => :string,
              0x5F => :string,
            }.freeze

            ACTIONS = {
              escape: lambda do |_scanner|
                consume_and_clear(1)
                "\e"
              end,
              csi: ->(_scanner) { parse_csi_sequence(prefix_bytes: 2, output_prefix: nil) },
              ss3: ->(_scanner) { parse_ss3_sequence },
              osc: ->(scanner) { parse_string_sequence(scanner.osc_terminator_index(2)) },
              string: ->(scanner) { parse_string_sequence(scanner.string_terminator_index(2)) },
              alt: ->(_scanner) { parse_decoded_character(1, prefix: "\e") },
            }.freeze

            def initialize(buffer, decoder)
              @buffer = buffer
              @decoder = decoder
              @scanner = DecoderScanner.new(buffer)
            end

            def parse
              action = HANDLERS.fetch(@buffer.getbyte(1), :alt)
              @decoder.instance_exec(@scanner, &ACTIONS.fetch(action))
            end
          end
        end
      end
    end
  end
end
