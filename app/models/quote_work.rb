# JOB-09: how a quote's work is shared among its jobs. Each job holds a claim on the quote lines
# it does (JobClaim); a quote line's claimed_quantity is the sum of its live claims, and the
# database refuses more than the line's quantity, so two people can't both take the same trees.
#
# Lock order, everywhere a claim changes (here, PAY-06, QTE-09, QTE-10, JOB-11): the quote, its
# jobs by id, then the quote's lines by id. Work entries take only the job's lock (they don't
# claim), and visits the job's then their own, so nothing waits on a lock earlier in the order.
#
# Behind the split_jobs flag (on only once PAY-06 and PAY-08 ship) asking for more than is free
# is refused. With it off a quote has one job, as before, and a job line raised past the quote
# claims only what's free; claims are kept either way.
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
  def follow!(job_line, lines)
    claim = job_line.claim
    return unless claim && (line = lines[claim.quote_line_item_id])

    wanted = job_line.quantity.to_d
    held = claim.quantity.to_d
    if wanted > held + line.to_do_quantity
      raise Refused, refusal(line, wanted - held) if split?(job_line.business)

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

  # PAY-01's invoice from a quote with no live job bills its lines directly: each invoice line
  # claims what's still free of its quote line, with no job, so it isn't offered as to do.
  def claim_direct!(invoice, quote)
    return if quote.jobs.where.not(status: "cancelled").exists?

    lines = lock!(quote.id)
    quote.line_items.sort_by { [ _1.position, _1.id ] }.zip(invoice.line_items.sort_by { [ _1.position, _1.id ] }).each do |quote_line, invoice_line|
      line = lines.fetch(quote_line.id)
      quantity = [ invoice_line&.quantity.to_d, line.to_do_quantity ].min
      next unless invoice_line && quantity.positive?

      JobClaim.create!(business: invoice.business, quote_line_item: line, invoice_line_item: invoice_line, quantity:)
      bump!(line, quantity)
    end
  end

  # PAY-06's direct billing, until it takes this over: a claim with no job is freed when its
  # invoice line is deleted (a draft deleted, a line removed) and stops being live when the invoice
  # is voided (`keep`), so the quote's lines stay reconciled.
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

  # "Tree removal: 4 of 10 to do (J-0002 has 6), not 5."
  def refusal(line, wanted)
    held = line.claims.live.where.not(job_id: nil).includes(:job).order(:job_id).map { "#{_1.job.number} has #{number(_1.quantity)}" }
    "#{line.name.presence || "Item"}: #{number(line.to_do_quantity)} of #{number(line.quantity)} to do" \
      "#{" (#{held.to_sentence})" if held.any?}, not #{number(wanted)}."
  end

  def number(value) = value.to_d.round(4).to_s("F").sub(/\.?0+\z/, "")
end
