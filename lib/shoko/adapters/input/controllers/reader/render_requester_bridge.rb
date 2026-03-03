# frozen_string_literal: true

require_relative '../../../../core/ports/outbound/reader_render_requester'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Adapter bridge that translates render requests into controller redraw calls.
          class RenderRequesterBridge
            include Shoko::Core::Ports::Outbound::ReaderRenderRequester

            def initialize(controller:, logger: nil)
              @controller = controller
              @logger = logger
            end

            def request_render(reason:)
              @controller.force_redraw
              @controller.draw_screen
            rescue RuntimeError, SystemCallError, IOError, ArgumentError => e
              @logger&.debug('reader.render_request.failed',
                             reason: reason,
                             error: e.class.name,
                             message: e.message)
              raise Shoko::Core::Ports::Outbound::ReaderRenderRequester::RenderRequestError,
                    "Render request failed (#{reason}): #{e.message}"
            end
          end
        end
      end
    end
  end
end
