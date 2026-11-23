require "test_helper"

# PLT-17: one colour language. Every status of every record type is in the map, with the staff
# pages' words, and each record's pill takes its tone from it.
class StatusHelperTest < ActionView::TestCase
  include ComponentsHelper
  include QuotesHelper
  include InvoicesHelper
  include JobsHelper
  include AutomationsHelper

  MAP = StatusHelper::MAP

  def current_business = businesses(:one)

  setup { Current.business = current_business }
  teardown { Current.reset }
  def labels(type) = MAP.fetch(type).transform_values(&:last)
  def tone_class(html) = Nokogiri::HTML5.fragment(html).css(".badge").map { (_1["class"].split.grep(/\Abadge-(?!plain)/).first || "badge-neutral").delete_prefix("badge-").to_sym }

  # The owner's map (2026-11-22), as the spec's Decisions record it.
  test "the map is the owner's" do
    expected = {
      success: { quote: %w[approved], job: %w[completed], visit: %w[completed], invoice: %w[paid], request: %w[quoted], follow_up: %w[done],
                 automation: %w[on], automation_run: %w[done], support_ticket: %w[resolved] },
      info: { quote: %w[sent], invoice: %w[sent partially_paid], job: %w[scheduled in_progress], visit: %w[scheduled in_progress],
              automation_run: %w[scheduled], support_ticket: %w[open] },
      warning: { quote: %w[changes_requested], job: %w[unscheduled], request: %w[new in_progress], support_ticket: %w[waiting], quota: %w[approaching] },
      neutral: { quote: %w[draft expired archived], invoice: %w[draft void], job: %w[cancelled], visit: %w[cancelled], request: %w[archived],
                 automation: %w[off], automation_run: %w[skipped], quota: %w[ok] },
      danger: { quote: %w[declined], invoice: %w[overdue], follow_up: %w[overdue], email: %w[not_delivered], automation_run: %w[failed], quota: %w[blocked] }
    }
    # Owner, 2026-11-23: the other pills follow the same meanings.
    expected[:info][:email] = %w[sent]
    expected[:neutral].merge!(client_import_row: %w[new], payment: %w[closed])
    expected[:success][:payment] = %w[won prevented]
    expected.each do |tone, types|
      types.each do |type, statuses|
        statuses.each { assert_equal tone, status_tone(type, _1), "#{type} #{_1}" }
      end
    end
    assert_equal StatusHelper::MEANINGS.keys.sort, MAP.values.flat_map { _1.values.map(&:first) }.uniq.sort, "only the five meanings"
  end

  test "every status of every record type is in the map, in the models' words" do
    assert_equal Quote::STATUS_LABELS.merge("sent" => "Sent", "expired" => "Expired", "archived" => "Archived", "update_requested" => "Update requested"), labels(:quote)
    assert_equal Job::LABELS, labels(:job)
    assert_equal Visit::LABELS, labels(:visit)
    assert_equal Invoice::STATUS_LABELS.merge("overdue" => "Overdue"), labels(:invoice)
    assert_equal ServiceRequest::LABELS, labels(:request)
    assert_equal AutomationRun::STATUSES.sort, MAP[:automation_run].keys.sort
    assert_equal SupportTicket::STATUSES, labels(:support_ticket)
    assert_equal PaymentAccount::STATUSES.sort.to_h, labels(:payment_account).sort.to_h
    assert_equal Payment::DISPUTE_STATUSES.keys.sort, (MAP[:payment].keys - %w[refunded partly_refunded]).sort
    Payment::DISPUTE_STATUSES.each { |key, label| assert_equal label, labels(:payment)[key] }
    EmailMessage::STATUSES.each { assert_equal EmailMessage.new(status: _1).status_label, labels(:email).fetch(_1) }
    assert_equal %w[ok approaching blocked], MAP[:quota].keys
    assert_equal StatusHelper::TYPE_NAMES.keys, MAP.keys
  end

  test "each record's pill takes its tone from the map" do
    Job::STATUSES.each { assert_equal [ status_tone(:job, _1) ], tone_class(job_status_badge(Job.new(status: _1))), "job #{_1}" }
    Visit::STATUSES.each { assert_equal [ status_tone(:visit, _1) ], tone_class(visit_status_badge(Visit.new(status: _1))), "visit #{_1}" }
    Invoice::STATUSES.each { assert_equal [ status_tone(:invoice, _1) ], tone_class(invoice_status_badge(Invoice.new(status: _1, business: current_business, due_on: current_business.today))), "invoice #{_1}" }
    overdue = Invoice.new(status: "sent", business: current_business, due_on: current_business.today - 1)
    assert_equal %i[info danger], tone_class(invoice_status_badge(overdue))
    Quote::STATUSES.each { assert_equal [ status_tone(:quote, _1) ], tone_class(quote_status_badge(Quote.new(status: _1, business: current_business))), "quote #{_1}" }
    expired = Quote.new(status: "sent", business: current_business, expires_on: current_business.today - 1)
    assert_equal [ :neutral ], tone_class(quote_status_badge(expired))
    assert_includes quote_status_badge(expired), "Expired"
    AutomationRun::STATUSES.each { assert_equal [ status_tone(:automation_run, _1) ], tone_class(automation_run_badge(AutomationRun.new(status: _1))) }
  end

  test "a pill says its status in words and names its map entry" do
    html = Nokogiri::HTML5.fragment(status_badge(:request, "in_progress"))
    assert_equal "In progress", html.at_css(".badge").text
    assert_equal "request:in_progress", html.at_css(".badge")["data-status"]
    assert_includes html.at_css(".badge")["class"], "badge-warning"
    assert_includes status_badge(:client_import_row, "duplicate", "Matches Maria Lopez"), "Matches Maria Lopez"
    assert_raises(KeyError) { status_badge(:request, "lost") }
  end
end
