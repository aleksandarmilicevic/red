require 'red/dsl/red_dsl'

include Red::Dsl

module RedLib
module Web

  machine_model do
    abstract machine WebClient, {
      auth_token: String
    }

    abstract machine WebServer, {
      online_clients: (set WebClient)
    } do
      def client_disconnected(client)
        Red.boss.fireClientDisconnected(:client => client)
      end
    end    
  end

  event_model do
    event ClientConnected do
      from client: WebClient
      to   server: WebServer

      ensures {
        server.online_clients << client
        server.save!
      }
    end

    event ClientDisconnected do
      from client: WebClient
      to   server: WebServer

      ensures {
        # server.online_clients.delete(client)
        server.online_clients = server.online_clients - [client]
        server.save!
      }
    end
  end

end
end
