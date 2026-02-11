# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Ports::ReaderOverlayReader do
  let(:implementation) do
    Class.new do
      include Shoko::Core::Ports::ReaderOverlayReader
    end.new
  end

  it 'defines required overlay reader methods' do
    expect { implementation.mode }.to raise_error(NotImplementedError)
    expect { implementation.selection }.to raise_error(NotImplementedError)
    expect { implementation.popup_menu }.to raise_error(NotImplementedError)
    expect { implementation.in_book_search_popup }.to raise_error(NotImplementedError)
    expect { implementation.annotations_overlay }.to raise_error(NotImplementedError)
    expect { implementation.annotation_editor_overlay }.to raise_error(NotImplementedError)
    expect { implementation.dictionary_popup }.to raise_error(NotImplementedError)
    expect { implementation.dictionary_panel }.to raise_error(NotImplementedError)
    expect { implementation.running? }.to raise_error(NotImplementedError)
    expect { implementation.sidebar_visible? }.to raise_error(NotImplementedError)
    expect { implementation.sidebar_active_tab }.to raise_error(NotImplementedError)
  end
end
