# PLT-17: one colour language. A tone means one thing everywhere, and every status pill on staff
# pages takes its tone from MAP, so a status looks the same on its own page, in lists, on the
# client page, on Home, in My day and in Notifications. The style guide shows the whole map.
#
#   status_badge(:request, request.status, request.status_label)
#   status_tone(:invoice, "partially_paid") # => :info
#
# Each pill says its status in words too, so colour is never the only signal. A new status goes
# here first (StatusHelperTest fails until it does).
module StatusHelper
  MEANINGS = { success: "Done or money in", info: "Waiting on someone else", warning: "Needs you",
               neutral: "Not started or closed", danger: "Failed or overdue" }.freeze

  # type => { status => [tone, label] }. Labels are the staff pages' words (the tests keep them
  # in step with the models'). The owner's map, 2026-11-22; visits, runs, tickets and the meter
  # kept their tones (#332), as did the other pills listed after the meter.
  MAP = {
    quote: { "draft" => [ :neutral, "Draft" ], "sent" => [ :info, "Sent" ], "changes_requested" => [ :warning, "Changes requested" ],
             "approved" => [ :success, "Approved" ], "declined" => [ :danger, "Declined" ], "expired" => [ :neutral, "Expired" ],
             "archived" => [ :neutral, "Archived" ], "update_requested" => [ :warning, "Update requested" ] },
    job: { "unscheduled" => [ :warning, "Unscheduled" ], "scheduled" => [ :info, "Scheduled" ], "in_progress" => [ :info, "In progress" ],
           "completed" => [ :success, "Completed" ], "cancelled" => [ :neutral, "Cancelled" ] },
    visit: { "scheduled" => [ :info, "Scheduled" ], "in_progress" => [ :info, "In progress" ], "completed" => [ :success, "Completed" ],
             "cancelled" => [ :neutral, "Cancelled" ] },
    invoice: { "draft" => [ :neutral, "Draft" ], "sent" => [ :info, "Sent" ], "partially_paid" => [ :info, "Partly paid" ],
               "paid" => [ :success, "Paid" ], "void" => [ :neutral, "Void" ], "overdue" => [ :danger, "Overdue" ] },
    request: { "new" => [ :warning, "New" ], "in_progress" => [ :warning, "In progress" ], "quoted" => [ :success, "Quoted" ],
               "archived" => [ :neutral, "Archived" ] },
    follow_up: { "done" => [ :success, "Done" ], "overdue" => [ :danger, "Overdue" ] },
    automation: { "on" => [ :success, "On" ], "off" => [ :neutral, "Off" ] },
    automation_run: { "scheduled" => [ :info, "Waiting" ], "done" => [ :success, "Done" ], "skipped" => [ :neutral, "Skipped" ],
                      "failed" => [ :danger, "Didn't finish" ] },
    support_ticket: { "open" => [ :info, "Open" ], "waiting" => [ :warning, "Waiting on you" ], "resolved" => [ :success, "Resolved" ] },
    quota: { "ok" => [ :neutral, "Within the limit" ], "approaching" => [ :warning, "Nearly used" ], "blocked" => [ :danger, "Limit reached" ] },
    # A client email (NTF-01's record): one that didn't arrive is danger wherever it shows.
    email: { "queued" => [ :neutral, "Sending" ], "sent" => [ :success, "Sent" ], "bounced" => [ :danger, "Address refused" ],
             "failed" => [ :danger, "Couldn't send" ], "suppressed" => [ :danger, "Not sent: address blocked" ],
             "pending" => [ :info, "Waiting" ], "not_delivered" => [ :danger, "Email not delivered" ] },
    payment: { "refunded" => [ :warning, "Refunded" ], "partly_refunded" => [ :warning, "Partly refunded" ], "open" => [ :danger, "Disputed" ],
               "won" => [ :warning, "Dispute won" ], "lost" => [ :danger, "Dispute lost" ], "closed" => [ :danger, "Inquiry closed" ],
               "prevented" => [ :danger, "Dispute prevented" ] },
    payment_account: { "active" => [ :success, "Active" ], "pending_verification" => [ :info, "Pending verification" ],
                       "onboarding_incomplete" => [ :warning, "Setup not finished" ], "restricted" => [ :danger, "Restricted" ] },
    client_import_row: { "new" => [ :success, "New" ], "duplicate" => [ :warning, "Matches a client" ], "invalid" => [ :danger, "Won't import" ] }
  }.freeze

  # The record types, as the style guide names them.
  TYPE_NAMES = { quote: "Quotes", job: "Jobs", visit: "Visits", invoice: "Invoices", request: "Requests", follow_up: "Request follow-ups",
                 automation: "Automations", automation_run: "Automation runs", support_ticket: "Support tickets", quota: "Quote meter (BIL-06)",
                 email: "Client emails", payment: "Payments", payment_account: "Payments account", client_import_row: "Client import rows" }.freeze

  def status_tone(type, status) = MAP.fetch(type).fetch(status.to_s).first

  # A status pill from the map. label: the words, when they say more than the map's (a count,
  # a name); data-status names the entry, for the design-system check.
  def status_badge(type, status, label = nil, **attributes)
    tone, default = MAP.fetch(type).fetch(status.to_s)
    badge(label || default, tone:, data: { status: "#{type}:#{status}" }, **attributes)
  end
end
