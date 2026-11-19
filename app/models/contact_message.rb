# MKT-02: a message sent through the marketing site's contact form. Platform-level: it belongs
# to no business, and staff app users never see it; operators do, in the console
# (Ops::ContactMessagesController), where they mark it handled once answered.
#
# Saved, then the team is emailed (reply goes straight to the sender) and the sender gets a
# confirmation with nothing they typed in it, so the form can't carry a message to anyone else. One that looks like spam is kept with its reason, for review, and nobody is
# emailed. Kept two years, spam 30 days (PruneContactMessagesJob); `erase_for!` removes a
# person's messages on request.
class ContactMessage < ApplicationRecord
  RETENTION = 2.years
  SPAM_RETENTION = 30.days
  ABUSE_DETAILS_RETENTION = 30.days
  MAX_LINKS = 2
  SPAM_WORDS = /\b(?:casino|viagra|cialis|backlinks?|guest posts?|crypto ?currency investment|forex signals?|payday loans?)\b/i
  # One confirmation per address in this time, so the form can't be used to flood someone's inbox.
  CONFIRMATION_INTERVAL = 1.hour

  before_validation { self.uid ||= SecureRandom.base58(BusinessOwned::UID_LENGTH) }
  before_validation :tidy

  validates :name, presence: true, length: { maximum: 120 }
  validates :email, presence: true, length: { maximum: 254 }, format: { with: /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/, allow_blank: true }
  validates :business_name, length: { maximum: 120 }
  validates :industry, inclusion: { in: ->(_) { Industry.keys + [ "other" ] }, allow_blank: true }
  validates :body, presence: true, length: { maximum: 5_000 }

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :spam, -> { where.not(spam_reason: nil) }
  scope :not_spam, -> { where(spam_reason: nil) }
  scope :unhandled, -> { where(handled_at: nil) }
  scope :handled, -> { where.not(handled_at: nil) }

  def to_param = uid
  def self.find_by_param!(param) = find_by!(uid: param.to_s)

  def spam? = spam_reason.present?
  def industry_name = industry == "other" ? "Other" : Industry.name_for(industry)

  # Saves it and, unless it looks like spam, queues the team's email and the sender's
  # confirmation (`notified_at`: when they were queued). Returns whether a confirmation is on its way.
  def submit!
    self.spam_reason = detect_spam
    save!
    return false if spam?

    ContactMailer.with(message: self).received.deliver_later
    update_column(:notified_at, Time.current)
    confirm = Rails.cache.write("contact-confirmation:#{Digest::SHA256.hexdigest(mailbox)}", 1, unless_exist: true, expires_in: CONFIRMATION_INTERVAL)
    ContactMailer.with(message: self).confirmation.deliver_later if confirm
    confirm
  end

  # Someone asked us to forget them: their messages go. Returns how many.
  def self.erase_for!(email) = where(email: email.to_s.strip.downcase).delete_all # stored lowercase

  # Old messages go; the IP address and browser (only for abuse checks) go after 30 days.
  def self.prune!
    where(created_at: ...ABUSE_DETAILS_RETENTION.ago).where.not(ip_address: nil).update_all(ip_address: nil, user_agent: nil)
    where(created_at: ...RETENTION.ago).delete_all + spam.where(created_at: ...SPAM_RETENTION.ago).delete_all
  end

  private

  # The address without a "+tag", so a+1@ and a+2@ count as one mailbox.
  def mailbox = email.sub(/\+[^@]*@/, "@")

  def tidy
    # Control and invisible formatting characters (such as text-direction overrides) go.
    self.name = name.to_s.gsub(/[[:cntrl:]\p{Cf}]/, " ").squish.presence
    self.email = email.to_s.strip.downcase.presence
    self.business_name = business_name.to_s.gsub(/[[:cntrl:]\p{Cf}]/, " ").squish.presence
    self.industry = industry.presence
    self.body = body.to_s.strip.presence
  end

  def detect_spam
    return "link in name" if name.to_s.match?(%r{https?://|www\.}i)
    return "too many links" if body.to_s.scan(%r{https?://|www\.}i).size > MAX_LINKS
    return "spam words" if body.to_s.match?(SPAM_WORDS)

    nil
  end
end
