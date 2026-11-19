# NTF-04: ready-made automations, switched on in one step (and editable after). A recipe that
# emails clients brings its own template of the business's own (NTF-03), created once.
module AutomationRecipe
  Recipe = Data.define(:key, :name, :description, :trigger, :delay_minutes, :conditions, :actions, :template)

  ALL = [
    Recipe.new("quote_follow_up", "Quote follow-up",
               "Three days after you send a quote, if it isn't answered, a friendly check-in goes to the client.",
               "quote_sent", 3 * 24 * 60, { "still_open" => true }, [ { "type" => "send_template" } ],
               { name: "Quote follow-up", subject: "Any questions about quote {{document_number}}?",
                 body: "Hi {{client_first_name}},\n\nJust checking in on the quote I sent. Happy to answer any questions or adjust anything.\n\n{{your_name}}" }),
    Recipe.new("overdue_reminder", "Overdue invoice reminder",
               "When an invoice passes its due date unpaid, the client gets a polite reminder.",
               "invoice_overdue", 0, { "still_open" => true }, [ { "type" => "send_template" } ],
               { name: "Payment reminder", subject: "Reminder: invoice {{document_number}}",
                 body: "Hi {{client_first_name}},\n\nA quick reminder that invoice {{document_number}} for {{total}} is now past due. You can see it with the button below.\n\nThanks,\n{{your_name}}" }),
    Recipe.new("job_on_approval", "Job when a quote is approved",
               "When a client approves a quote, a job is created from it, ready to schedule.",
               "quote_approved", 0, {}, [ { "type" => "create_job" } ], nil),
    Recipe.new("auto_invoice", "Invoice when the job is done",
               "When you complete a job, its invoice is created and emailed to the client.",
               "job_completed", 0, {}, [ { "type" => "invoice_job" } ], nil),
    Recipe.new("review_request", "Review request after payment",
               "A day after an invoice is paid in full, the client is asked how it went.",
               "payment_received", 24 * 60, { "paid_in_full" => true }, [ { "type" => "send_template" } ],
               { name: "Review request", subject: "How did we do?",
                 body: "Hi {{client_first_name}},\n\nThanks for choosing {{business_name}}. If you were happy with the work, a short review would mean a lot to us.\n\n{{your_name}}" })
  ].index_by(&:key).freeze

  def self.find(key) = ALL.fetch(key.to_s)

  # The recipe as a rule of the business's own (with its template), saved; or the rule with errors.
  def self.install!(key, by:)
    recipe = find(key)
    rule = nil
    AutomationRule.transaction do
      actions = recipe.actions.map do |action|
        next action unless action["type"] == "send_template"

        template = MessageTemplate.custom.find_by("lower(name) = ?", recipe.template[:name].downcase) ||
                   MessageTemplate.create!(**recipe.template, updated_by: by)
        action.merge("template" => template.uid)
      end
      rule = AutomationRule.create(name: recipe.name, trigger: recipe.trigger, delay_minutes: recipe.delay_minutes, conditions: recipe.conditions,
                                   actions:, recipe: recipe.key, created_by: by)
      raise ActiveRecord::Rollback unless rule.persisted?
    end
    rule
  end
end
