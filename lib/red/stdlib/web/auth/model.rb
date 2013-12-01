require 'red/stdlib/web/machine_model'

include Red::Dsl

module RedLib
module Web
module Auth

  def pswd_hash(str, salt)
    Digest::SHA256.hexdigest(str + salt)
  end

  #===========================================================
  # Data model
  #===========================================================

  data_model do
    abstract record AuthUser, {
      name: String,
      email: String,
      password_salt: String,
      password_hash: String,
      remember_token: String
    } do

      transient {{
          password: String
        }}

      before_validation { |user|
        user.email = user.email.downcase if user.email
        user.remember_token = SecureRandom.urlsafe_base64
        user.password_salt = SecureRandom.urlsafe_base64 unless self.password_salt        
        if user.password_hash
          user.password = "......" # it won't matter, passwors is already set
        else
          user.password_hash = pswd_hash(user.password, user.password_salt) rescue nil
        end
      }

      validates :name,  presence: true, length: { maximum: 50 }

      VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
      validates :email, presence: true,
                        format: { with: VALID_EMAIL_REGEX },
                        uniqueness: { case_sensitive: false }

      validates :password, presence: true, length: { minimum: 6 }

      validates :password_hash, presence: true

      def authenticate(pswd)
        password_hash == pswd_hash(pswd, self.password_salt)
      end

    end
  end

  #===========================================================
  # Machine model
  #===========================================================

  machine_model do
    abstract machine AuthClient < WebClient, {
      user: AuthUser
    }

    abstract machine AuthServer < WebServer
  end

  #===========================================================
  # Event model
  #===========================================================

  event_model do
    event Register do
      from client: AuthClient

      params {{
          name: String,
          email: String,
          password: String,
        }}

      requires {
        self.email = self.email.downcase
        AuthUser.where(:email => email).empty?
      }

      ensures {
        client.create_user! :name => name,
                            :email => email,
                            :password => password
        client.save
      }
    end

    event SignIn do
      from client: AuthClient

      params {{
          email: String,
          password: String
        }}

      requires {
        self.email = self.email.downcase
      }

      ensures {
        u = AuthUser.where(:email => email).first
        incomplete "User #{email} not found" unless u
        pswd_ok = u.authenticate(password)
        incomplete "Wrong password for user #{u.name} (#{email})" unless pswd_ok
        client.user = u
        client.save
      }
    end

    event SignOut do
      from client: AuthClient
      to   server: WebServer

      requires {
        client.user
      }

      ensures {
        client.user = nil
        server.client_disconnected(client)
        client.save
      }
    end

    event Unregister do
      from client: AuthClient

      requires {
        some client.user
      }

      ensures {
        client.user.destroy
        client.save
      }
    end
  end

end
end
end
