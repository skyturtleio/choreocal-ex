import Config

if System.get_env("PHX_SERVER") == "true" do
  config :choreocal, ChoreocalWeb.Endpoint, server: true
end

config :choreocal, ChoreocalWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  config :choreocal, ChoreocalWeb.Endpoint,
    live_reload: [patterns: [~r"priv/static/.*(js|css|svg)$", ~r"lib/choreocal_web/.*(ex|heex)$"]]
end

if config_env() == :prod do
  host = System.fetch_env!("PHX_HOST")
  config :choreocal, :token_signing_secret, System.fetch_env!("TOKEN_SIGNING_SECRET")
  config :choreocal, :mail_from, System.fetch_env!("MAIL_FROM")

  config :choreocal, Choreocal.Mailer,
    adapter: Swoosh.Adapters.Resend,
    api_key: System.fetch_env!("RESEND_API_KEY")

  config :choreocal, Choreocal.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
    log: false

  config :choreocal, ChoreocalWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: ["https://#{host}"],
    http: [ip: {0, 0, 0, 0}],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
else
  config :choreocal, :mail_from, "development@example.invalid"
  # Disposable orb databases use local Unix-socket peer authentication.
  config :choreocal, Choreocal.Repo,
    username: System.get_env("USER", "user"),
    password: nil,
    hostname: nil,
    socket_dir: "/var/run/postgresql",
    log: false
end
