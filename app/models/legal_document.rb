# MKT-03: Shadetree's legal and trust pages, each with its versions. The text of each version
# is a view (app/views/legal/documents/<slug>/<version>.html.erb) that is never edited once
# published: a change is a new version, with its effective date and a summary of what changed,
# and older versions stay readable at /legal/<slug>/<version>.
#
# `material: true` on a version means people who accepted an earlier one are asked to accept it
# on their next sign-in (only Terms and Privacy are accepted). Whether a change is material is
# the operator's call; it's set here, with the version.
#
# `draft: true` shows a "draft, pending legal review" banner (the text is drafted in-house and
# must be reviewed before public launch, 11-marketing open question 2).
class LegalDocument
  Version = Data.define(:version, :effective_on, :summary, :material, :draft) do
    def initialize(version:, effective_on:, summary:, material: false, draft: false) = super
  end

  attr_reader :slug, :title, :description, :versions

  def initialize(slug, title, description, versions)
    @slug, @title, @description = slug, title, description
    @versions = versions.map { Version.new(**_1) }.sort_by(&:effective_on).reverse.freeze
  end

  def current = versions.find { _1.effective_on <= Date.current } || versions.last
  def version(id) = versions.find { _1.version == id.to_s }
  def template(version = current) = "legal/documents/#{slug}/#{version.version}"
  def accepted? = ACCEPTED.include?(slug)

  # The newest material version in force, which anyone who accepted an older one must accept.
  def required_version = versions.select { _1.material && _1.effective_on <= Date.current }.max_by(&:effective_on)

  # The first published version. Not material: everyone who signed up before it accepted the
  # placeholder terms, and is taken to have accepted this (their version is blank).
  FIRST = { version: "2026-11-18", effective_on: Date.new(2026, 11, 18), summary: "First version.", draft: true }.freeze
  ACCEPTED = %w[terms privacy].freeze

  ALL = [
    new("terms", "Terms of Service", "The agreement between your business and Shadetree.", [ FIRST ]),
    new("privacy", "Privacy Policy", "What we collect about you, why, and your choices.", [ FIRST ]),
    new("acceptable-use", "Acceptable Use Policy", "What Shadetree can't be used for.", [ FIRST ]),
    new("data-processing", "Data Processing Summary", "How we handle your clients' data on your behalf.", [ FIRST ]),
    new("subprocessors", "Sub-processors", "The companies that help us run Shadetree.", [ FIRST ]),
    new("security", "Security & Trust", "How we protect your data.", [ FIRST ])
  ].index_by(&:slug).freeze

  def self.find(slug) = ALL.fetch(slug.to_s) { raise ActiveRecord::RecordNotFound, "No legal document #{slug}" }
  def self.terms = find("terms")
  def self.privacy = find("privacy")

  # The versions someone accepting today agrees to: { "terms" => "2026-11-18", "privacy" => ... }.
  def self.current_versions = ACCEPTED.to_h { [ _1, find(_1).current.version ] }

  # Accepted documents with a material version newer than the one this user accepted.
  def self.needing_acceptance(user)
    ACCEPTED.map { find(_1) }.select do |document|
      required = document.required_version
      required && user.public_send(:"#{document.slug}_version").to_s < required.version
    end
  end
end
