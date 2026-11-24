# A living reference for the UI kit (PLT-05). Routed in development and test only.
class StyleguideController < ApplicationController
  class SampleRecord
    include ActiveModel::Model

    attr_accessor :name, :email, :notes, :timezone, :visit_on, :starts_at, :price, :reminders

    validates :name, presence: true
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }

    def self.model_name = ActiveModel::Name.new(self, nil, "Sample")
    def persisted? = false
  end

  def show
    @valid = SampleRecord.new(name: "Maria Lopez", email: "maria@example.com", timezone: "America/New_York", price: "1250.00", reminders: true)
    @invalid = SampleRecord.new(name: "", email: "maria@").tap(&:validate)
    flash.now[:notice] = "Quote sent to Maria Lopez." if params[:toast] == "1"
    flash.now[:alert] = "Couldn't send the quote. Try again in a minute." if params[:toast] == "error"
  end

  def client
    @business = Business.new(name: "Oakline Lawn & Landscape", brand_color: params.fetch(:brand, "#9a3412"), phone: "(555) 010-4477")
    render layout: "client"
  end
end
