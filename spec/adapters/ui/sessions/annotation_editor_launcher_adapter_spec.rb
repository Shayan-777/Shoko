# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Sessions::AnnotationEditorLauncherAdapter do
  let(:annotation_overlay_ui_session) { instance_double(Shoko::Adapters::Ui::Sessions::AnnotationOverlayUiSessionAdapter, open_editor: :ok) }
  subject(:adapter) { described_class.new(annotation_overlay_ui_session: annotation_overlay_ui_session) }

  it 'delegates editor opening to annotation overlay session' do
    result = adapter.open_editor(
      text: 'selected',
      chapter_index: 3,
      annotation: { id: 'ann-1' }
    )

    expect(result).to eq(:ok)
    expect(annotation_overlay_ui_session).to have_received(:open_editor).with(
      text: 'selected',
      chapter_index: 3,
      annotation: { id: 'ann-1' }
    )
  end
end
