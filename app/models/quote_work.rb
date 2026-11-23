# JOB-09: how a quote's work is shared among its jobs. Each job holds a claim on the quote lines
# it does (JobClaim); a quote line's claimed_quantity is the sum of its live claims, and the
# database refuses more than the line's quantity, so two people can't both take the same trees.
#
# Lock order, everywhere a claim changes (here, PAY-06, QTE-09, QTE-10, JOB-11): the quote, its
# jobs by id, then the quote's lines by id. Work entries take only the job's lock (they don't
# claim), and visits the job's then their own, so nothing waits on a lock earlier in the order.
#
# Behind the split_jobs flag (on only once PAY-06 and PAY-08 ship) a job takes what staff pick,
# and asking for more than is free is refused. With it off a quote has one job, as before, and a
# job line raised past the quote claims only what's free; claims are kept either way.
module QuoteWork
  FLAG = :split_jobs

  # Refused: the lines named didn't have that much to do. The transaction rolls back.
  class Refused < StandardError; end

  module_function

  def split?(business) = Feature.enabled?(FLAG, business:)

  # Takes the locks in order and returns the quote's lines, fresh, by id. The quote row and the
  # jobs are locked without reloading, so a record with unsaved changes keeps them.
  def lock!(quote_id, jobs: [])
    Quote.where(id: quote_id).lock.pluck(:id)
    Job.where(id: Array(jobs).map { _1.is_a?(Job) ? _1.id : _1 }).order(:id).lock.pluck(:id)
    QuoteLineItem.where(quote_id:).order(:id).lock.to_a.index_by(&:id)
  end

  # Moves a line's claimed quantity by delta. The check backs up the callers' own test: a
  # violation rolls back to the savepoint and is reported as a refusal naming the line.
  def bump!(line, delta)
    return if delta.zero?

    QuoteLineItem.transaction(requires_new: true) do
      QuoteLineItem.where(id: line.id).update_all([ "claimed_quantity = claimed_quantity + ?", delta ])
    end
    line.reload # for later checks in this transaction (the column is read-only to saves)
  rescue ActiveRecord::CheckViolation
    raise Refused, refusal(line.reload, delta)
  end

  # Claims `quantity` of a locked line for a job (more of it when the job already has some).
  def claim!(job, line, quantity, job_line: nil)
    quantity = quantity.to_d
    raise Refused, refusal(line, quantity) if quantity > line.to_do_quantity

    claim = job.claims.find_or_initialize_by(quote_line_item: line)
    claim.quantity = claim.quantity.to_d + quantity
    claim.job_line_item ||= job_line
    claim.save!
    bump!(line, quantity)
    claim
  end

  # A job line's quantity changed on an open job (the job form): its claim follows, taking free
  # quantity or freeing the difference. Past what's free is refused with the flag on (that needs
  # a change order, QTE-10), and claims only what's free with it off.
  # Lowering a line that's still past what it can claim (an old line above the quote) is allowed:
  # only an increase is refused.
  def follow!(job_line, lines)
    claim = job_line.claim
    return unless claim && (line = lines[claim.quote_line_item_id])

    wanted = job_line.quantity.to_d
    held = claim.quantity.to_d
    if wanted > held + line.to_do_quantity
      raise Refused, refusal(line, wanted - held) if split?(job_line.business) && wanted > job_line.quantity_before_last_save.to_d

      wanted = held + line.to_do_quantity
    end
    claim.update!(quantity: wanted)
    bump!(line, wanted - held)
  end

  # A quote line removed from an open job: what it held is to do again.
  def unclaim!(claim, lines)
    line = lines.fetch(claim.quote_line_item_id)
    bump!(line, -claim.quantity.to_d)
    claim.delete
  end

  # PAY-06's direct billing: an invoice line that's the final bill of a quote line with no job
  # claims what's free of it, up to its quantity, so no job can take that work; a draft's autosave
  # moves the claim with the line's quantity (more only from what's free). The caller holds the
  # quote's lock (WorkBilling, or the invoice's save).
  def claim_direct!(invoice_line)
    line = lock!(invoice_line.quote_line_item.quote_id).fetch(invoice_line.quote_line_item_id)
    quantity = [ invoice_line.quantity.to_d, line.to_do_quantity ].min
    return unless quantity.positive?

    JobClaim.create!(business: invoice_line.business, quote_line_item: line, invoice_line_item: invoice_line, quantity:)
    bump!(line, quantity)
  end

  def follow_direct!(claim, wanted)
    line = lock!(claim.quote_line_item.quote_id).fetch(claim.quote_line_item_id)
    wanted = [ wanted.to_d, claim.quantity.to_d + line.to_do_quantity ].min
    bump!(line, wanted - claim.quantity.to_d)
    claim.update!(quantity: wanted)
  end

  # A claim with no job is freed when its invoice line is deleted (a draft deleted, a line removed)
  # and stops being live when the invoice is voided (`keep`), so the quote's lines stay reconciled.
  def release_direct!(claims, keep: false)
    claims = claims.where(job_id: nil).includes(:quote_line_item).to_a
    claims.group_by { _1.quote_line_item.quote_id }.each do |quote_id, held|
      lines = lock!(quote_id)
      held.sort_by(&:quote_line_item_id).each do |claim|
        bump!(lines.fetch(claim.quote_line_item_id), -claim.quantity.to_d)
        claim.delete unless keep
      end
    end
  end

  # Cancelling: the job's claims stop being live, so their quantities are to do again. The claims
  # are kept for a reopen.
  def release!(job, lines)
    job.claims.sort_by(&:quote_line_item_id).each { bump!(lines.fetch(_1.quote_line_item_id), -_1.quantity.to_d) }
  end

  # Reopening a cancelled job: it takes back what it held, refused while any of it is in another
  # job (or billed directly).
  def reclaim!(job, lines)
    claims = job.claims.sort_by(&:quote_line_item_id)
    short = claims.select { _1.quantity.to_d > lines.fetch(_1.quote_line_item_id).to_do_quantity }
    if short.any?
      raise Refused, "#{job.number} can't be reopened while its work is in another job. " +
                     short.map { refusal(lines.fetch(_1.quote_line_item_id), _1.quantity) }.join(" ")
    end

    claims.each { bump!(lines.fetch(_1.quote_line_item_id), _1.quantity.to_d) }
  end

  # Completing: each line's quantity becomes what was done, and what it booked is kept for a
  # reopen. A claim never shrinks (a shortfall isn't freed); more done than booked claims free
  # quantity (kept apart as the claim's extra), and more than the quote has is refused: interim
  # until QTE-10's change orders. A legacy line already past the quote keeps what it booked.
  def confirm!(job, done, lines)
    job.line_items.each do |job_line|
      quantity = done.fetch(job_line.id, job_line.quantity).to_d
      raise Refused, "#{job_line.name}: what was done can't be less than zero." if quantity.negative?

      if (claim = job_line.claim) && (line = lines[claim.quote_line_item_id]) && quantity > claim.quantity.to_d
        extra = quantity - claim.quantity.to_d
        if extra > line.to_do_quantity && quantity > job_line.quantity.to_d
          raise Refused, "#{job_line.name}: #{number(quantity)} is more than the quote has to do (#{number(claim.quantity.to_d + line.to_do_quantity)}). " \
                         "Lower it, or change the quote first."
        end
        taken = [ extra, line.to_do_quantity ].min
        claim.update!(quantity: claim.quantity.to_d + taken, extra_quantity: claim.extra_quantity.to_d + taken)
        bump!(line, taken)
      end
      job_line.update_columns(quantity:, booked_quantity: job_line.quantity, updated_at: Time.current)
    end
  end

  # Reopening a completed job: its lines go back to what they booked, and what completion took for
  # more done than booked is free again.
  def restore_booked!(job, lines)
    job.line_items.each do |job_line|
      job_line.update_columns(quantity: job_line.booked_quantity, booked_quantity: nil, updated_at: Time.current) if job_line.booked_quantity
      claim = job_line.claim
      next unless claim&.extra_quantity.to_d.positive? && (line = lines[claim.quote_line_item_id])

      bump!(line, -claim.extra_quantity.to_d)
      claim.update!(quantity: claim.quantity.to_d - claim.extra_quantity.to_d, extra_quantity: 0)
    end
  end

  # The picker's ticked rows ({ line key => { take:, quantity: } }) as { quote line id => quantity },
  # by the lines' keys within this quote: another quote's (or business's) lines aren't found.
  def picks_from(quote, rows)
    return {} unless rows.respond_to?(:key?)

    quote.line_items.each_with_object({}) do |line, picks|
      row = rows[line.key]
      next unless row.respond_to?(:key?) && ActiveModel::Type::Boolean.new.cast(row[:take])

      picks[line.id] = row[:quantity].to_s.strip.presence || "0"
    end
  end

  # "Tree removal: 4 of 10 to do (J-0002 has 6), not 5."
  def refusal(line, wanted)
    held = line.claims.live.where.not(job_id: nil).includes(:job).order(:job_id).map { "#{_1.job.number} has #{number(_1.quantity)}" }
    "#{line.name.presence || "Item"}: #{number(line.to_do_quantity)} of #{number(line.quantity)} to do" \
      "#{" (#{held.to_sentence})" if held.any?}, not #{number(wanted)}."
  end

  def number(value) = value.to_d.round(4).to_s("F").sub(/\.?0+\z/, "")
end
