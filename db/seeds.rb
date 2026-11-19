# Seeds must be idempotent: bin/setup runs them on every setup.
#
# - Records every environment needs (reference data) belong in this file.
# - Demo data for local development lives in db/seeds/development.rb.
#   Each feature spec adds seeds for the records it introduces.

# Industry starter services (CAT-05): adds missing industries, never overwrites operator edits.
IndustryPreset.sync!

# Plans (BIL-01): adds missing plans, never overwrites operator edits.
Plan.sync!

load Rails.root.join("db/seeds/development.rb") if Rails.env.development?
