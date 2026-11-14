# Every form_with/form_for gets the kit's field helpers (f.field, f.check, f.submit_button).
ActiveSupport.on_load(:action_view) do
  ActionView::Base.default_form_builder = ShadetreeFormBuilder
end
