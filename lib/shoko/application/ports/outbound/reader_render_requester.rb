# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port for requesting a reader render pass from application orchestration.
        module ReaderRenderRequester
          class RenderRequestError < StandardError; end

          def request_render(reason:)
            raise NotImplementedError, "#{self.class} must implement #request_render"
          end
        end
      end
    end
  end
end
