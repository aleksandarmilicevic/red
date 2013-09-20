require 'red/dsl/red_dsl'

include Red::Dsl

module RedLib
module Web

  machine_model do
    abstract machine WebClient, {
      auth_token: String
    }

    abstract machine WebServer
  end

end
end
