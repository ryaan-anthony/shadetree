require "test_helper"

# JOB-09: a quote's work shared among jobs through claims: splits, refusals, the picker's token,
# raising and lowering on the job form, cancel and both reopens, completion and the database's
# check. Every test ends reconciled: each line's claimed quantity is the sum of its live claims.
class QuoteWorkTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @quote = as_business(@business) do
      client = Client.create!(display_name: "Pat Lee", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ], properties_attributes: [ { address_line1: "4 Oak Rd", billing: true } ])
      quote = Quote.start(client:, created_by: @owner)
      quote.title = "Yard work"
      quote.set_discount("amount", "50")
      quote.sync_line_items([ { "key" => "t", "name" => "Tree removal", "quantity" => "10", "unit_price" => "100" },
                              { "key" => "g", "name" => "Gutters", "quantity" => "1", "unit_price" => "200", "discount_kind" => "percent", "discount_value" => "10" },
                              { "key" => "h", "name" => "Haul away", "quantity" => "2", "unit_price" => "40", "discount_kind" => "amount", "discount_value" => "5" } ])
      quote.save!
      quote.mark_sent!(by: @owner, channel: "link")
      @business.update!(auto_create_jobs: false)
      quote.record_response!(:approve, by: @owner, signer_name: "Pat Lee", message: "By phone")
      quote.reload
    end
  end

  teardown { assert_empty as_business(@business) { JobClaim.unreconciled_lines.pluck(:id) }, "claimed = the sum of live claims" }

  def line(key) = as_business(@business) { @quote.line_items.find_by!(key:).reload }
  def pick(**quantities) = quantities.to_h { [ line(_1.to_s).id, _2.to_s ] }
  def split! = enable_feature(:split_jobs)
  def make(**quantities) = as_business(@business) { Job.from_quote!(@quote, by: @owner, picks: pick(**quantities)) }

  test "flag off: one job takes everything with its discounts, and a second press opens it" do
    job = as_business(@business) { Job.from_quote!(@quote, by: @owner) }
    as_business(@business) do
      assert_equal [ "Yard work", "amount", 5_000 ], [ job.title, job.discount_kind, job.discount_amount_cents ]
      assert_equal [ [ "Tree removal", 10 ], [ "Gutters", 1 ], [ "Haul away", 2 ] ], job.line_items.map { [ _1.name, _1.quantity.to_i ] }
      assert_equal [ 10, 1, 2 ], @quote.line_items.map { _1.reload.claimed_quantity.to_i }
      assert_equal job.line_items.map(&:id), job.claims.order(:quote_line_item_id).map(&:job_line_item_id)
      assert_equal job, Job.from_quote!(@quote)
    end
  end

  test "split: jobs take parts of lines, with titles from their lines and no fixed discounts" do
    split!
    first = make(t: 6)
    second = make(t: 4, g: 1, h: 2)
    as_business(@business) do
      assert_equal "Tree removal (6 of 10)", first.title
      assert_equal "Tree removal (4 of 10), Gutters, Haul away", second.title
      assert_nil first.discount_kind, "the quote's $50 off is shared on invoices (PAY-08)"
      assert_equal [ "percent", nil ], second.line_items.drop(1).map(&:discount_kind), "a percent line discount is copied; a fixed one isn't"
      assert_equal [ 10, 1, 2 ], @quote.line_items.map { _1.reload.claimed_quantity.to_i }
      assert_equal [ 0, 0, 0 ], @quote.line_items.map { _1.to_do_quantity.to_i }
      error = assert_raises(Job::NotOpen) { Job.from_quote!(@quote) }
      assert_equal "Everything on quote #{@quote.number} is already in #{first.number} and #{second.number}.", error.message
    end
  end

  test "a job taking everything has the quote's title" do
    split!
    assert_equal "Yard work", make(t: 10, g: 1, h: 2).title
  end

  test "asking for more than is to do is refused, naming the jobs that hold it" do
    split!
    first = make(t: 6)
    error = assert_raises(QuoteWork::Refused) { make(t: 5) }
    assert_equal "Tree removal: 4 of 10 to do (#{first.number} has 6), not 5.", error.message
    assert_equal 1, as_business(@business) { @quote.jobs.count }
    assert_raises(Job::NotOpen) { make(t: 0) }
  end

  test "a resubmitted picker opens the job it made" do
    split!
    job = as_business(@business) { Job.from_quote!(@quote, picks: pick(t: 3), token: "tok-1") }
    again = as_business(@business) { Job.from_quote!(@quote, picks: pick(t: 3), token: "tok-1") }
    assert_equal job, again
    assert_equal 3, line("t").claimed_quantity
  end

  test "without picks a split job takes everything still to do" do
    split!
    make(t: 6)
    job = as_business(@business) { Job.from_quote!(@quote) }
    assert_equal [ 4, 1, 2 ], as_business(@business) { job.line_items.map { _1.quantity.to_i } }
  end

  test "NTF-04's Create job takes everything to do, or is skipped saying why" do
    split!
    first = make(t: 6)
    as_business(@business) do
      result, detail = AutomationActions.create_job({}, @quote, nil)
      made = @quote.jobs.last
      assert_equal [ "done", "Created #{made.number}." ], [ result, detail ]
      assert_equal [ 4, 1, 2 ], made.line_items.map { _1.quantity.to_i }
      assert_equal [ "skipped", "Everything on quote #{@quote.number} is already in #{first.number} and #{made.number}." ], AutomationActions.create_job({}, @quote, nil)
    end
  end

  test "flag off: NTF-04 skips a quote that has its job" do
    job = as_business(@business) { Job.from_quote!(@quote) }
    assert_equal [ "skipped", "#{job.number} already exists." ], as_business(@business) { AutomationActions.create_job({}, @quote, nil) }
  end

  test "the automatic job on approval takes everything" do
    split!
    quote = as_business(@business) do
      @business.update!(auto_create_jobs: true)
      client = @quote.client
      q = Quote.start(client:)
      q.sync_line_items([ { "key" => "a", "name" => "Mowing", "quantity" => "3", "unit_price" => "40" } ])
      q.save!
      q.mark_sent!(by: @owner, channel: "link")
      q.record_response!(:approve, by: @owner, signer_name: "Pat Lee", message: "By phone")
      q
    end
    as_business(@business) do
      assert_equal [ [ "Mowing", 3 ] ], quote.reload.jobs.sole.line_items.map { [ _1.name, _1.quantity.to_i ] }
      assert_equal 3, quote.line_items.first.claimed_quantity
    end
  end

  test "another business's lines aren't taken" do
    split!
    other = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Other", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      Quote.start(client:).tap { _1.sync_line_items([ { "key" => "x", "name" => "Theirs", "quantity" => "1", "unit_price" => "1" } ]) && _1.save! }
    end
    other_line = as_business(businesses(:two)) { other.line_items.first }
    assert_raises(Job::NotOpen) { as_business(@business) { Job.from_quote!(@quote, picks: { other_line.id => "1" }) } }
    assert_equal 0, as_business(businesses(:two)) { other_line.reload.claimed_quantity }
  end

  test "the job form: raising takes free quantity, past it is refused; lowering and removing free it" do
    split!
    job = make(t: 6, g: 1)
    trees, gutters = as_business(@business) { job.line_items.to_a }
    as_business(@business) do
      job.update!(line_items_attributes: [ { id: trees.id, quantity: "8" }, { id: gutters.id } ])
      assert_equal 8, line("t").claimed_quantity
      error = assert_raises(QuoteWork::Refused) { job.reload.update!(line_items_attributes: [ { id: trees.id, quantity: "11" }, { id: gutters.id } ]) }
      assert_match "Tree removal: 2 of 10 to do (#{job.number} has 8), not 3.", error.message
      job.reload.update!(line_items_attributes: [ { id: trees.id, quantity: "5" }, { id: gutters.id, _destroy: "1" } ])
      assert_equal [ 5, 0 ], [ line("t").claimed_quantity, line("g").claimed_quantity ]
      assert_equal [ 5 ], job.reload.claims.map { _1.quantity.to_i }
    end
  end

  test "flag off: a job line raised past the quote claims only what's free, as before" do
    job = as_business(@business) { Job.from_quote!(@quote) }
    as_business(@business) do
      trees = job.line_items.first
      job.update!(line_items_attributes: job.line_items.map { { id: _1.id } }.tap { _1[0][:quantity] = "12" })
      assert_equal [ 12, 10 ], [ trees.reload.quantity.to_i, line("t").claimed_quantity.to_i ]
    end
  end

  test "cancelling frees the work and reopening takes it back" do
    job = as_business(@business) { Job.from_quote!(@quote) }
    as_business(@business) { job.cancel!(by: @owner, notify_client: false) }
    assert_equal [ 0, 0, 0 ], %w[t g h].map { line(_1).claimed_quantity.to_i }
    assert_equal [ 10, 1, 2 ], as_business(@business) { job.claims.order(:quote_line_item_id).map { _1.quantity.to_i } }, "kept for a reopen"
    as_business(@business) { job.reload.reopen! }
    assert_equal [ 10, 1, 2 ], %w[t g h].map { line(_1).claimed_quantity.to_i }
  end

  test "removing a quote line from a job frees it" do
    job = as_business(@business) { Job.from_quote!(@quote) }
    as_business(@business) do
      rows = job.line_items.map { { id: _1.id } }
      rows[0][:quantity] = "4"
      rows[1][:_destroy] = "1"
      job.update!(line_items_attributes: rows)
      assert_equal [ 4, 0, 2 ], @quote.line_items.map { _1.reload.claimed_quantity.to_i }
    end
  end


  test "cancelling frees the work; reopening is refused while another job holds it" do
    split!
    first = make(t: 6)
    as_business(@business) { first.cancel!(by: @owner, notify_client: false) }
    assert_equal 0, line("t").claimed_quantity
    second = make(t: 5)
    error = assert_raises(QuoteWork::Refused) { as_business(@business) { first.reload.reopen! } }
    assert_match "#{first.number} can't be reopened while its work is in another job.", error.message
    assert_match "(#{second.number} has 5)", error.message
    as_business(@business) { second.cancel!(by: @owner, notify_client: false) }
    as_business(@business) { first.reload.reopen! }
    assert_equal [ "unscheduled", 6 ], [ first.reload.status, line("t").claimed_quantity ]
  end

  test "completing confirms what was done: logged totals, a shortfall kept, more done claims free, past the quote refused" do
    split!
    job = make(t: 6, g: 1)
    trees, gutters = as_business(@business) { job.line_items.to_a }
    as_business(@business) do
      WorkEntry.create!(job:, job_line_item: trees, user: @owner, quantity: 4)
      WorkEntry.create!(job:, job_line_item: trees, user: users(:two), quantity: 1)
      assert_equal({ trees.id => 5, gutters.id => 1 }, job.done_so_far.transform_values(&:to_i))
      job.complete!(by: @owner)
      assert_equal [ 5, 1 ], job.reload.line_items.map { _1.quantity.to_i }
      assert_equal 6, line("t").claimed_quantity, "the shortfall isn't freed"
      assert_equal 5 * 10_000 + 18_000, job.subtotal_cents, "totals follow the done quantities"
    end

    other = make(t: 2)
    as_business(@business) do
      more = other.line_items.first
      error = assert_raises(QuoteWork::Refused) { other.complete!(by: @owner, done: { more.id => 5 }) }
      assert_match "Tree removal: 5 is more than the quote has to do (4)", error.message
      other.reload.complete!(by: @owner, done: { more.id.to_s => "4" })
      assert_equal [ 4, 10 ], [ more.reload.quantity.to_i, line("t").claimed_quantity.to_i ]
    end
  end

  test "reopening a completed job is refused while an invoice bills it; otherwise its lines go back to what they booked" do
    split!
    job = make(t: 6)
    trees = as_business(@business) { job.line_items.first }
    as_business(@business) { job.complete!(by: @owner, done: { trees.id => 5 }) }
    invoice = as_business(@business) { Invoice.from_job!(job.reload, by: @owner) }
    error = assert_raises(Job::NotOpen) { as_business(@business) { job.reload.reopen! } }
    assert_equal "#{job.number} can't be reopened while #{invoice.number} bills it. Void it first.", error.message
    as_business(@business) { invoice.update_columns(status: "void") }
    as_business(@business) { job.reload.reopen! }
    assert_equal [ 6, 6 ], [ trees.reload.quantity.to_i, line("t").claimed_quantity.to_i ]
  end

  test "flag off: reopening a completed, invoiced job works as before" do
    job = as_business(@business) { Job.from_quote!(@quote) }
    as_business(@business) { job.complete!(by: @owner) && Invoice.from_job!(job.reload) }
    as_business(@business) { job.reload.reopen! }
    assert_predicate job.reload, :open?
  end

  test "to-do work can be added to an open job" do
    split!
    job = make(t: 3)
    as_business(@business) { job.reload.add_from_quote!(pick(t: 2, g: 1)) }
    as_business(@business) do
      assert_equal [ [ "Tree removal", 5 ], [ "Gutters", 1 ] ], job.reload.line_items.map { [ _1.name, _1.quantity.to_i ] }
      assert_equal [ 5, 1 ], [ line("t").claimed_quantity, line("g").claimed_quantity ]
      assert_equal job.totals.total.cents, job.total_cents
    end
  end

  test "the database refuses claims past a line's quantity, or below zero" do
    trees = line("t")
    as_business(@business) do
      [ 11, -1 ].each do |claimed|
        assert_raises(ActiveRecord::CheckViolation) { QuoteLineItem.transaction(requires_new: true) { QuoteLineItem.where(id: trees.id).update_all(claimed_quantity: claimed) } }
      end
    end
  end

  test "work entries are only ever added" do
    job = as_business(@business) { Job.from_quote!(@quote) }
    entry = as_business(@business) { WorkEntry.create!(job:, job_line_item: job.line_items.first, user: @owner, quantity: 2) }
    as_business(@business) do
      assert_raises(ActiveRecord::ReadOnlyRecord) { entry.update!(quantity: 3) }
      assert_raises(ActiveRecord::ReadOnlyRecord) { entry.destroy! }
    end
  end

  test "an invoice straight from a quote with no job claims its lines; voiding or deleting it frees them" do
    sent = as_business(@business) { Invoice.from_quote!(@quote) }
    draft = as_business(@business) { Invoice.from_quote!(@quote) }
    assert_equal [ 10, 1, 2 ], %w[t g h].map { line(_1).claimed_quantity.to_i }
    assert_equal 0, as_business(@business) { JobClaim.joins(:invoice_line_item).where(invoice_line_items: { invoice_id: draft.id }).count }, "nothing left for a second one"
    job = as_business(@business) { Job.from_quote!(@quote) }
    assert_equal [ [ 10, 0 ], [ 1, 0 ], [ 2, 0 ] ], as_business(@business) { job.line_items.map { [ _1.quantity.to_i, _1.claim.quantity.to_i ] } }, "flag off: a job copies the quote in full, claiming only what's free"
    as_business(@business) do
      job.cancel!(by: @owner, notify_client: false)
      sent.update_columns(sent_at: Time.current)
      sent.void!(reason: "Wrong client", by: @owner)
    end
    assert_equal [ 0, 0, 0 ], %w[t g h].map { line(_1).claimed_quantity.to_i }
    another = as_business(@business) { Invoice.from_quote!(@quote) }
    assert_equal 10, line("t").claimed_quantity
    as_business(@business) { another.destroy! }
    assert_equal 0, line("t").claimed_quantity
  end

  test "removing a job line keeps its work log" do
    job = as_business(@business) { Job.from_quote!(@quote) }
    trees = as_business(@business) { job.line_items.first }
    as_business(@business) do
      WorkEntry.create!(job:, job_line_item: trees, user: @owner, quantity: 3)
      job.update!(line_items_attributes: job.line_items.map { { id: _1.id } }.tap { _1[0][:_destroy] = "1" })
      entry = WorkEntry.sole
      assert_equal [ nil, "Tree removal", 3, @owner.id ], [ entry.job_line_item_id, entry.item_name, entry.quantity.to_i, entry.user_id ]
    end
  end

  test "reopening a completed job that did more than booked frees the extra and goes back to what it booked" do
    split!
    job = make(t: 6)
    trees = as_business(@business) { job.line_items.first }
    as_business(@business) { job.complete!(by: @owner, done: { trees.id => 8 }) }
    assert_equal [ 8, 8 ], [ trees.reload.quantity.to_i, line("t").claimed_quantity.to_i ]
    as_business(@business) { job.reload.reopen! }
    assert_equal [ 6, 6, nil ], [ trees.reload.quantity.to_i, line("t").claimed_quantity.to_i, trees.booked_quantity ]
  end

  test "an old line already past the quote can be lowered; only increases are refused" do
    job = as_business(@business) { Job.from_quote!(@quote) }
    trees = as_business(@business) { job.line_items.first }
    as_business(@business) { trees.update_columns(quantity: 12) }
    split!
    rows = ->(quantity) { as_business(@business) { job.reload.line_items.map { { id: _1.id } }.tap { _1[0][:quantity] = quantity } } }
    as_business(@business) { job.reload.update!(line_items_attributes: rows.("11")) }
    assert_equal [ 11, 10 ], [ trees.reload.quantity.to_i, line("t").claimed_quantity.to_i ]
    assert_raises(QuoteWork::Refused) { as_business(@business) { job.reload.update!(line_items_attributes: rows.("13")) } }
  end

  test "adding work to an old job whose claim has no line gives the line all the claim holds" do
    job = as_business(@business) { Job.from_quote!(@quote) }
    as_business(@business) do
      job.line_items.first.claim.update_columns(job_line_item_id: nil, quantity: 6)
      job.line_items.first.delete
      QuoteLineItem.where(id: line("t").id).update_all(claimed_quantity: 6)
    end
    split!
    as_business(@business) { job.reload.add_from_quote!(pick(t: 2)) }
    as_business(@business) do
      added = job.reload.line_items.find_by!(name: "Tree removal")
      assert_equal [ 8, 8 ], [ added.quantity.to_i, added.claim.quantity.to_i ]
    end
  end

  test "a resubmitted picker whose job was cancelled asks again" do
    split!
    job = as_business(@business) { Job.from_quote!(@quote, picks: pick(t: 3), token: "tok-2") }
    as_business(@business) { job.cancel!(by: @owner, notify_client: false) }
    error = assert_raises(Job::NotOpen) { as_business(@business) { Job.from_quote!(@quote, picks: pick(t: 3), token: "tok-2") } }
    assert_match "was cancelled. Choose the work again.", error.message
  end
end

# Two people taking the same trees at the same moment: the quote's lock queues the second, which
# finds them taken.
class QuoteWorkRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "two pickers asking for the same trees: one job gets them" do
    business = businesses(:one)
    Feature.overrides["split_jobs"] = true
    quote = as_business(business) do
      client = Client.create!(display_name: "Race", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      Quote.start(client:).tap do
        _1.sync_line_items([ { "key" => "t", "name" => "Trees", "quantity" => "10", "unit_price" => "100" } ])
        _1.save!
        _1.update_columns(status: "approved")
      end
    end
    line_id = as_business(business) { quote.line_items.first.id }
    results = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          as_business(business) { Job.from_quote!(Quote.find(quote.id), picks: { line_id => "6" }) && :made }
        rescue QuoteWork::Refused
          :refused
        end
      end
    end.map(&:value)
    assert_equal %i[made refused], results.sort
    assert_equal [ 6, 1 ], as_business(business) { [ QuoteLineItem.find(line_id).claimed_quantity.to_i, Job.where(quote_id: quote.id).count ] }
  ensure
    if quote
      as_business(business) do
        client_id = quote.client_id
        Job.where(client_id:).delete_all
        Quote.where(id: quote.id).delete_all
        Client.find(client_id).destroy!
      end
      ActiveRecord::Base.connection.execute("DELETE FROM document_sequences WHERE business_id = #{business.id.to_i}")
    end
  end
end
