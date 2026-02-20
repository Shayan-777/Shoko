# frozen_string_literal: true

# Predeclare top-level namespaces so shorthand module definitions
# (e.g., `module Adapters::Monitoring`) remain load-order safe.
module Shoko
  module Adapters
    module BookSources; end
    module Input; end
    module Monitoring; end
    module Output
      module Clipboard; end
      module Formatting; end
      module Kitty; end
      module Rendering; end
      module Terminal; end
      module Ui; end
    end
    module Runtime; end
    module State; end
    module Storage; end
  end

  module Application
    module Composition; end
    module Controllers; end
    module Ports; end
    module Services; end
    module Ui; end
    module UseCases; end
  end

  module Core
    module BookFormats; end
    module Events; end
    module Models; end
    module Ports; end
    module Services; end
  end

  module Shared; end
end
