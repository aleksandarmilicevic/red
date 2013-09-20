require_relative 'red_dsl_test_helper.rb'

module IRC
  module Model

    #===========================================================
    # Data model
    #===========================================================
    data_model "Data" do
      record User, {
        name: String
      }

      record Msg, {
        text: String,
        sender: User
      }

      record ChatRoom, {
        name: String,
        members: (set User),
        messages: (seq Msg)
      }
    end

    #===========================================================
    # Machine model
    #===========================================================
    machine_model "Machine" do
      machine Client, {
        user: User
      }

      machine Server, {
        clients: (set Client),
        rooms: (set ChatRoom)
      }
    end

    #===========================================================
    # Event model
    #===========================================================
    event_model "Event" do

      #------------------------------------------------------
      # Event +SignIn+
      #------------------------------------------------------
      event SignIn do
        from client: Client
        to   serv: Server

        params {{
          name: String,
          xyz: Integer
        }}

        requires {
          no u: User | u.name == name
        }

        ensures {
          u = new User
          u.name = name
          client.user = u
          serv.clients += client
        }
      end

      #------------------------------------------------------
      # Event +CreateRoom+
      #------------------------------------------------------
      event CreateRoom do
        from client: Client
        to   serv: Server

        params {{
          roomName: String
        }}

        requires {
          (some client.user) &&
          (no r: serv.rooms | r.name == roomName)
        }

        ensures {
          room = new ChatRoom
          room.name = roomName
          room.members = client.user
          serv.rooms += room
        }
      end

      #------------------------------------------------------
      # Event +JoinRoom+
      #------------------------------------------------------
      event JoinRoom do
        from client: Client
        to   serv: Server

        params {{
          room: ChatRoom
        }}

        requires {
          some client.user
        }

        ensures {
          room.members += client.user
        }
      end

      #------------------------------------------------------
      # Event +SendMsg+
      #------------------------------------------------------
      event SendMsg do
        from client: Client
        to   serv: Server

        params {{
          room: ChatRoom,
          msgText: String
        }}

        requires {
          (some client.user) &&
          (room.members.member? client.user)
        }

        ensures {
          msg = new Msg
          msg.text = msgText
          msg.sender = client.user
          room.messages += msg
        }
      end
    end

  end
end

puts IRC::Model::Data::User.to_alloy
puts IRC::Model::Data::Msg.to_alloy
puts IRC::Model::Data::ChatRoom.to_alloy

puts Red.meta.records
puts Red.meta.machines
puts Red.meta.events

