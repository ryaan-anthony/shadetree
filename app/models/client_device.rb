# Coarse, non-identifying device description for client link views: "Phone · Safari".
module ClientDevice
  BROWSERS = [ [ /Edg\//, "Edge" ], [ /OPR\/|Opera/, "Opera" ], [ /Firefox\//, "Firefox" ],
               [ /Chrome\//, "Chrome" ], [ /Safari\//, "Safari" ] ].freeze

  def self.describe(user_agent)
    agent = user_agent.to_s
    return "Unknown" if agent.blank?

    kind = if agent.match?(/iPad|Tablet/i) then "Tablet"
    elsif agent.match?(/Mobi|iPhone|Android/i) then "Phone"
    else "Computer"
    end
    browser = BROWSERS.find { |pattern, _| agent.match?(pattern) }&.last || "Other browser"
    "#{kind} · #{browser}"
  end
end
