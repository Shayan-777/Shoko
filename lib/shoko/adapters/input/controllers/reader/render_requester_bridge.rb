# frozen_string_literal: true

require 'shoko/application/ports/outbound/reader_render_requester'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Adapter bridge that posts render requests to the reader controller.
          # The request only marks a pending redraw and wakes the event loop's
          # blocked input read — the frame itself is always drawn on the UI
          # thread, so requesters may call this from worker threads.
          class RenderRequesterBridge
            include Shoko::Application::Ports::Outbound::ReaderRenderRequester

            def initialize(controller:)
              @controller = controller
            end

            # The port carries the reason for requesters' own logging; posting
            # the flag has no failure mode worth recording here.
            def request_render(reason:) # rubocop:disable Lint/UnusedMethodArgument
              @controller.request_render
            end
          end
        end
      end
    end
  end
end
