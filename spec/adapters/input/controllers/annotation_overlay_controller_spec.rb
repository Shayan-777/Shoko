# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::AnnotationOverlayController do
  let(:reader_state) { instance_double('ReaderStateReader', book_path: '/books/test.epub', annotations: []) }
  let(:state_writer) { instance_double('StateWriter', update_reader: nil, clear_selection: nil, update_sidebar: nil) }
  let(:session) { instance_double('AnnotationOverlayUiSession', close_editor: nil, editor_context: nil) }
  let(:notification_service) { instance_double('NotificationService', set_message: nil) }

  subject(:controller) do
    described_class.new(
      reader_state: reader_state,
      state_writer: state_writer,
      annotation_overlay_ui_session: session,
      notification_service: notification_service
    )
  end

  it 'ignores non-hash editor payloads from session outcomes' do
    allow(session).to receive(:editor_insert_char).with('a').and_return(
      Shoko::Shared::Contracts::SessionOutcome.success(
        status: :handled,
        code: :editor_insert_char_handled,
        payload: 1.2345
      )
    )

    expect { controller.annotation_editor_insert_char('a') }.not_to raise_error
    expect(controller.annotation_editor_insert_char('a')).to eq(:handled)
  end

  it 'saves annotation when editor session returns a save event payload' do
    annotation_service = instance_double('AnnotationService', add: nil)
    allow(session).to receive(:editor_save).and_return(
      Shoko::Shared::Contracts::SessionOutcome.success(
        status: :handled,
        code: :annotation_editor_save_handled,
        payload: { type: :save, note: 'my note' }
      )
    )
    allow(session).to receive(:editor_context).and_return(
      annotation_id: nil,
      selected_text: 'selected text',
      note: 'my note',
      selection_range: { start: 3, end: 9 },
      chapter_index: 2
    )

    controller_with_service = described_class.new(
      reader_state: reader_state,
      state_writer: state_writer,
      annotation_overlay_ui_session: session,
      annotation_service: annotation_service,
      notification_service: notification_service
    )

    controller_with_service.annotation_editor_save

    expect(annotation_service).to have_received(:add).with(
      '/books/test.epub',
      'selected text',
      'my note',
      { start: 3, end: 9 },
      2,
      nil
    )
    expect(session).to have_received(:close_editor)
    expect(state_writer).to have_received(:clear_selection)
  end
end
