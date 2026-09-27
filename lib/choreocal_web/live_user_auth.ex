defmodule ChoreocalWeb.LiveUserAuth do
  use ChoreocalWeb, :verified_routes
  import Phoenix.LiveView

  def on_mount(:live_user_required, _params, _session, socket) do
    if user = socket.assigns[:current_user] do
      if connected?(socket),
        do: Phoenix.PubSub.subscribe(Choreocal.PubSub, "user:#{user.id}:auth")

      {:cont,
       attach_hook(socket, :auth_revocation, :handle_info, fn
         :auth_revoked, socket -> {:halt, redirect(socket, to: ~p"/sign-in")}
         _, socket -> {:cont, socket}
       end)}
    else
      {:halt, redirect(socket, to: ~p"/sign-in")}
    end
  end

  def disconnect(user),
    do: Phoenix.PubSub.broadcast(Choreocal.PubSub, "user:#{user.id}:auth", :auth_revoked)
end
