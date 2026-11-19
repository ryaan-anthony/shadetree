# A secure link that lets a client open one document (a quote, a visit, an invoice) without an
# account (PLT-12, ADR 0016). It grants exactly that document and the actions listed on it.
#
#   link = ClientLink.issue!(quote, actions: %w[approve], by: current_user)
#   client_link_url(link.token)               # https://…/c/9fK…  (send this to the client)
#   link.revoke!(by: current_user)            # the old URL now shows "this link is no longer active"
#   new_link = link.reissue!(by: current_user)
#
# The token is derived from a random per-link secret and the app's secret_key_base, and only
# its SHA-256 digest is used for lookup: a database copy alone can't produce working links.
class ClientLink < ApplicationRecord
  include BusinessOwned

  TOKEN_LENGTH = 32
  DEFAULT_LIFETIME = 90.days
  ACTIONS = %w[approve decline pay request_changes].freeze
  ONE_TIME_ACTIONS = %w[approve decline pay].freeze

  belongs_to :linkable, polymorphic: true
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :revoked_by, class_name: "User", optional: true
  has_many :events, class_name: "ClientLinkEvent", dependent: :delete_all

  validate :linkable_in_same_business
  validate { errors.add(:actions, "include unknown actions: #{(actions - ACTIONS).join(", ")}") if (actions - ACTIONS).any? }

  before_validation(on: :create) do
    self.secret ||= SecureRandom.hex(32)
    self.token_digest ||= self.class.digest(token)
  end

  scope :active, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  class << self
    # Expiry for a new link: the document's own policy (client_link_expires_at, where nil means
    # it doesn't expire, as for an unpaid invoice) or 90 days.
    def issue!(linkable, actions: [], expires_at: :default, by: nil)
      if expires_at == :default
        expires_at = linkable.respond_to?(:client_link_expires_at) ? linkable.client_link_expires_at : DEFAULT_LIFETIME.from_now
      end
      create!(linkable:, business: linkable.business, actions: actions.map(&:to_s), expires_at:, created_by: by)
    end

    # The only cross-business lookup a client request makes. Malformed tokens never hit the
    # database; well-formed ones are matched by digest, never compared directly.
    def find_by_token(token)
      return nil unless token.is_a?(String) && token.match?(/\A[1-9A-HJ-NP-Za-km-z]{#{TOKEN_LENGTH}}\z/o)

      link = Tenancy.across_businesses(reason: "client link lookup") do
        includes(:business).find_by(token_digest: digest(token))
      end
      # Tokens derive from secret_key_base: after a rotation, old URLs stop matching (ADR 0016).
      link if link && ActiveSupport::SecurityUtils.secure_compare(link.token, token)
    end

    def digest(token) = OpenSSL::Digest::SHA256.hexdigest(token)
  end

  def token
    raw = OpenSSL::HMAC.digest("SHA256", Rails.application.secret_key_base, "client_link:#{secret}")
    base58(raw).first(TOKEN_LENGTH)
  end

  # The partial that renders the document on the client page. Document types override it by
  # defining client_link_partial (e.g. "client/quotes/quote").
  def self.partial_for(document)
    document.try(:client_link_partial) || "client_links/documents/#{document.model_name.element}"
  end

  # :active, :expired, :revoked or :unavailable (business suspended).
  def status
    return :unavailable unless business.active?
    return :revoked if revoked_at
    return :expired if expires_at&.past?

    :active
  end

  def usable? = status == :active
  def allows?(action) = usable? && actions.include?(action.to_s)

  def revoke!(by: nil)
    as_own_business { update!(revoked_at: Time.current, revoked_by: by) unless revoked_at }
  end

  # A new link for the same document and actions; this one stops working.
  def reissue!(by: nil, expires_at: :default)
    as_own_business do
      revoke!(by:)
      self.class.issue!(linkable, actions:, expires_at:, by:)
    end
  end

  # Records a client view. Staff previews don't call this.
  def record_view!(device: nil)
    now = Time.current
    first = as_own_business do
      events.create!(business:, kind: "view", device:, occurred_at: now)
      self.class.where(id:).update_all([ "views_count = views_count + 1, last_viewed_at = ?", now ])
      self.class.where(id:, first_viewed_at: nil).update_all(first_viewed_at: now) == 1 # only one request wins
    end
    reload
    notify_first_view if first
    self
  end

  # Runs a one-time client action (approve, pay…) at most once per link. Returns false if the
  # action isn't allowed or already happened; the block runs inside the same transaction.
  def perform_once!(action, device: nil)
    action = action.to_s
    raise ArgumentError, "#{action} is not a one-time action" unless ONE_TIME_ACTIONS.include?(action)

    as_own_business(requires_new: true) do
      # Re-read under a lock so a revoke committed after this request loaded the link wins.
      lock!
      return false unless allows?(action)
      return false unless record_once(action, device)

      yield if block_given?
    end
    true
  end

  def performed?(action) = Tenancy.with_business(business) { events.exists?(kind: action.to_s) }

  def request_fresh_link!(device: nil)
    as_own_business do
      events.create!(business:, kind: "fresh_link_requested", device:, occurred_at: Time.current)
      update!(fresh_link_requested_at: Time.current)
    end
  end

  private

  # Inserts the one-time event in its own savepoint; false if it already exists. Errors from the
  # action itself are not swallowed.
  def record_once(action, device)
    transaction(requires_new: true) { events.create!(business:, kind: action, device:, occurred_at: Time.current) }
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # NTF-02: the office team hears when a client first opens a quote or an invoice (PAY-02).
  # deliver never raises.
  def notify_first_view
    Tenancy.with_business(business) do
      kind, path = case linkable
      when Quote then [ "quote", Rails.application.routes.url_helpers.admin_quote_path(linkable) ]
      when Invoice then [ "invoice", Rails.application.routes.url_helpers.admin_invoice_path(linkable) ]
      else return
      end
      NotificationType.deliver("#{kind}_viewed", business:, subject: linkable, title: "#{linkable.client.display_name} opened #{kind} #{linkable.number}",
                               body: linkable.title, path:)
    end
  end

  # Client requests already run as the link's business; this keeps model calls safe from jobs
  # and the console too.

  def as_own_business(requires_new: false, &block)
    Tenancy.with_business(business) { transaction(requires_new:, &block) }
  end

  BASE58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".freeze

  def base58(bytes)
    number = bytes.unpack1("H*").to_i(16)
    output = +""
    while number.positive?
      number, remainder = number.divmod(58)
      output << BASE58[remainder]
    end
    output.reverse.rjust(TOKEN_LENGTH, "1")
  end

  def linkable_in_same_business
    errors.add(:linkable, "belongs to another business") if linkable && linkable.business_id != business_id
  end
end
