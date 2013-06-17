require 'red/dsl/red_dsl'

include Red::Dsl

module RedLib
module Web

  machine_model do 
    abstract_machine WebClient, {
      auth_token: String
    } 
    
    abstract_machine WebServer, {
    } 
  end

end
end
