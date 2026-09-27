defmodule Choreocal.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ChoreocalWeb.Telemetry,
      Choreocal.Repo,
      {DNSCluster, query: Application.get_env(:choreocal, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Choreocal.PubSub},
      # Start a worker by calling: Choreocal.Worker.start_link(arg)
      # {Choreocal.Worker, arg},
      # Start to serve requests, typically the last entry
      ChoreocalWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :choreocal]}
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Choreocal.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ChoreocalWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
