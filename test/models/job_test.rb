require "test_helper"

# JOB-01: jobs from approved quotes and from scratch, statuses, numbering and the list's queries.
class JobTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ], properties_attributes: [ { address_line1: "12 Elm St", billing: true, access_notes: "Gate code 4417" } ])
      TaxRate.create!(name: "State", percent: "6.25")
    end
  end

  def approved_quote(title: "Spring cleanup")
    as_business(@business) do
      quote = Quote.start(client: @maria, created_by: users(:one))
      quote.title = title
      quote.internal_notes = "Bring the big mower"
      quote.set_discount("percent", "10")
      quote.sync_line_items([ { "key" => "a", "name" => "Leaf cleanup", "quantity" => "2", "unit" => "hour", "unit_price" => "90" },
                              { "key" => "b", "name" => "Mulch", "quantity" => "6", "unit" => "cu yd", "unit_price" => "78", "taxable" => "0" } ])
      quote.save!
      quote.attachments.attach(io: file_fixture("logo.png").open, filename: "yard.png", content_type: "image/png")
      quote.mark_sent!(by: users(:one), channel: "link")
      @business.update!(auto_create_jobs: false)
      quote.record_response!(:approve, by: users(:one), signer_name: "Maria Lopez", message: "By phone")
      quote.reload
    end
  end

  test "an approved quote becomes a job with its client, property, items, notes, files and pricing" do
    quote = approved_quote
    job = as_business(@business) { Job.from_quote!(quote, by: users(:one)) }
    as_business(@business) do
      assert_equal [ @maria, @maria.properties.first, quote, "Spring cleanup", "Bring the big mower", "unscheduled" ],
                   [ job.client, job.property, job.quote, job.title, job.internal_notes, job.status ]
      assert_match(/\AJ-\d{4}\z/, job.number)
      assert_equal [ [ "Leaf cleanup", "2 hours", 9_000, true ], [ "Mulch", "6 cu yd", 7_800, false ] ],
                   job.line_items.map { [ _1.name, _1.quantity_label, _1.unit_price_cents, _1.taxable ] }
      assert_equal [ "yard.png" ], job.attachments.map { _1.filename.to_s }
      assert_equal quote.total_cents, job.total_cents, "same items, discount and tax as the quote"
      assert_equal quote.tax_rates, job.tax_rates
      assert_equal job, quote.reload.job
      assert_equal job, Job.from_quote!(quote), "made once"
      assert_equal 1, Job.count
    end
  end

  test "a long first line or client name still makes a valid title, and a quote without a property uses the client's" do
    quote = as_business(@business) do
      q = Quote.start(client: @maria)
      q.update_columns(property_id: nil)
      q.sync_line_items([ { "key" => "a", "name" => "Remove and haul away " * 9, "quantity" => "1", "unit_price" => "10" } ])
      q.save!
      q.update_columns(status: "approved", property_id: nil)
      q.reload
    end
    job = as_business(@business) { Job.from_quote!(quote) }
    assert_operator job.title.length, :<=, 120
    assert_equal @maria.primary_property, as_business(@business) { job.property }
  end

  test "only an approved quote becomes a job" do
    as_business(@business) do
      draft = Quote.start(client: @maria)
      draft.save!
      assert_raises(Job::NotOpen) { Job.from_quote!(draft) }
    end
  end

  test "approving makes the job when the business has that on, and never undoes the approval" do
    quote = approved_quote # made with the setting off
    assert_nil as_business(@business) { quote.job }

    @business.update!(auto_create_jobs: true)
    second = as_business(@business) do
      q = Quote.start(client: @maria)
      q.sync_line_items([ { "key" => "a", "name" => "Hedges", "quantity" => "1", "unit_price" => "200" } ])
      q.save!
      q.mark_sent!(by: users(:one), channel: "link")
      q
    end
    as_business(@business) { second.record_response!(:approve, signer_name: "Maria Lopez", terms_accepted: true) } # as the client does, through their link
    job = as_business(@business) { second.reload.job }
    assert_equal "Hedges", job.title, "the first line names a quote without a title"
    assert_nil job.created_by

    third = as_business(@business) { Quote.start(client: @maria).tap { _1.save! && _1.mark_sent!(by: users(:one), channel: "link") } }
    as_business(@business) { @maria.archive! } # a job can't be made for an archived client
    as_business(@business) { third.record_response!(:approve, signer_name: "Maria Lopez", terms_accepted: true) }
    assert_equal "approved", as_business(@business) { third.reload.status }
    assert_nil as_business(@business) { third.job }
  end

  test "complete, cancel with a reason, and reopen" do
    job = as_business(@business) { Job.create!(client: @maria, property: @maria.primary_property, title: "Gutter clean") }
    as_business(@business) do
      job.complete!(by: users(:one))
      assert_equal [ "completed", users(:one) ], [ job.status, job.completed_by ]
      assert_raises(Job::NotOpen) { job.cancel!(by: users(:one)) }
      job.reopen!
      assert_equal [ "unscheduled", nil ], [ job.status, job.completed_at ]
      assert_raises(Job::NotOpen) { job.reopen! }
      job.cancel!(by: users(:one), reason: "  Moved away ")
      assert_equal [ "cancelled", "Moved away" ], [ job.status, job.cancel_reason ]
    end
  end

  test "a job from scratch gets the client's default taxes, and its property must be theirs" do
    as_business(@business) do
      job = Job.create!(client: @maria, property: @maria.primary_property, title: "Gutter clean")
      assert_equal [ "State" ], job.tax_rate_list.map(&:name)
      other = Client.create!(display_name: "Sam", contact_methods_attributes: [ { kind: "phone", value: "5550100101" } ], properties_attributes: [ { address_line1: "9 Oak Ave" } ])
      assert_not Job.new(client: @maria, property: other.properties.first, title: "x").valid?
      assert_not Job.new(client: @maria, property: @maria.primary_property, title: " ").valid?
      assert_includes Job.new(client: @maria, title: "x").tap(&:validate).errors.full_messages, "Property is needed: choose where the work happens"
      assert Job.new(client: Client.create!(display_name: "No place", contact_methods_attributes: [ { kind: "phone", value: "5550100102" } ]), title: "x").valid?,
             "a client without a property can still have a job"
      @maria.archive!
      assert_includes Job.new(client: @maria, title: "x").tap(&:validate).errors[:client], "is archived"
    end
  end

  test "filters, counts and search" do
    as_business(@business) do
      a = Job.create!(client: @maria, property: @maria.primary_property, title: "Gutter clean")
      b = Job.create!(client: @maria, property: @maria.primary_property, title: "Hedges").tap { _1.complete!(by: nil) }
      sam = Client.create!(display_name: "Sam Ortiz", contact_methods_attributes: [ { kind: "email", value: "sam@example.com" } ])
      c = Job.create!(client: sam, title: "Patio").tap { _1.cancel!(by: nil) }
      assert_equal [ a ], Job.filtered("open").to_a
      assert_equal [ a ], Job.filtered("unscheduled").to_a
      assert_equal({ "open" => 1, "unscheduled" => 1, "scheduled" => 0, "in_progress" => 0, "completed" => 1, "to_invoice" => 1, "cancelled" => 1, "all" => 3 }, Job.filter_counts)
      assert_equal [ c ], Job.search("ortiz").to_a
      assert_equal [ b ], Job.search("hedg").to_a
      assert_equal [ a ], Job.search(a.number).to_a
    end
  end

  test "jobs belong to one business and keep a client from being deleted" do
    job = as_business(@business) { Job.create!(client: @maria, property: @maria.primary_property, title: "Gutter clean") }
    assert_equal 0, as_business(businesses(:two)) { Job.count }
    as_business(@business) { assert_not @maria.reload.deletable? }
    assert job.persisted?
  end
end
