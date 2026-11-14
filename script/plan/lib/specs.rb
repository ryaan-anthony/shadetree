# frozen_string_literal: true

require "yaml"

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

# Shared loader for planning specs (docs/specs/**). Stdlib only, so it runs without bundler.
module Plan
  MILESTONES = {
    "M0" => "Foundation",
    "M1" => "Workspace",
    "M2" => "Quote → Approval",
    "M3" => "Schedule → Work",
    "M4" => "Invoice → Paid",
    "M5" => "Launch",
    "M6" => "Growth"
  }.freeze

  MILESTONE_DESCRIPTIONS = {
    "M0" => "The codebase is safe and pleasant for several developers/agents to work in at once.",
    "M1" => "A business can sign up, invite its team, describe itself and its services, and store clients.",
    "M2" => "Send a branded quote and get it approved online.",
    "M3" => "Turn approved work into scheduled visits that technicians complete.",
    "M4" => "Invoice and get paid online. MVP / private beta.",
    "M5" => "Everything needed to charge money and open sign-ups publicly.",
    "M6" => "Features that widen the funnel and deepen retention."
  }.freeze

  DOMAINS = {
    "platform" => "Stack, tenancy, CI/CD, security, conventions",
    "accounts" => "Sign-up, sign-in, businesses, team, roles, onboarding",
    "catalog" => "Business profile, branding, services, taxes, presets, hours",
    "clients" => "Client records, properties, request form, request inbox",
    "quotes" => "Build, send, view, approve, revise quotes",
    "jobs" => "Jobs, visits, calendar, technician day view",
    "payments" => "Invoices, online payments, recorded payments",
    "notifications" => "Email, team notifications, templates, automations",
    "billing" => "Our plans, usage limits and subscriptions",
    "operator" => "Internal operator console and support tickets",
    "marketing" => "Public website, legal pages, lead capture",
    "insights" => "Action dashboard, data export"
  }.freeze

  class CycleError < StandardError; end

  def self.milestone_index(milestone)
    MILESTONES.keys.index(milestone) || 99
  end

  Spec = Struct.new(:path, :meta, :body, :lines) do
    def id = meta["id"]
    def title = meta["title"]
    def domain = meta["domain"]
    def milestone = meta["milestone"]
    def depends_on = Array(meta["depends_on"])

    def section(name)
      body[/^## #{Regexp.escape(name)}\n(.*?)(?=^## |\z)/m, 1].to_s.strip
    end

    def summary = section("Summary").gsub(/\s*\n\s*/, " ")
    def acceptance_criteria = section("Acceptance criteria")
    def open_questions = section("Open questions")
  end

  module Specs
    def self.load(root = "docs/specs")
      Dir["#{root}/**/*.md"].reject { |f| File.basename(f).start_with?("_") }.sort.map do |path|
        text = File.read(path)
        _, front, body = text.split(/^---\s*$/, 3)
        raise "#{path}: missing front matter" unless body
        Spec.new(path, YAML.safe_load(front), body, text.lines.count)
      end
    end

    # Specs ordered so every spec comes after its dependencies (stable by milestone, then id).
    def self.topological(specs)
      by_id = specs.to_h { |s| [ s.id, s ] }
      state = {}
      out = []
      visit = lambda do |s, trail|
        raise CycleError, "dependency cycle: #{(trail + [ s.id ]).join(' -> ')}" if state[s.id] == :visiting
        return if state[s.id] == :done
        state[s.id] = :visiting
        s.depends_on.filter_map { |d| by_id[d] }.each { |d| visit.call(d, trail + [ s.id ]) }
        state[s.id] = :done
        out << s
      end
      specs.sort_by { |s| [ Plan.milestone_index(s.milestone), s.id ] }.each { |s| visit.call(s, []) }
      out
    end
  end
end
