defmodule ChoreocalWeb.PlannerComponents do
  use ChoreocalWeb, :html
  attr :title, :string, required: true
  attr :active, :string, default: "calendar"
  slot :inner_block, required: true

  def workspace(assigns) do
    ~H"""
    <div class="planner-shell" id="planner-workspace" phx-hook="UnsavedForms">
      <aside class="planner-sidebar">
        <.link navigate={~p"/"} class="wordmark">choreocal<span class="brand-dot">.</span></.link>
        <span class="eyebrow sidebar-label">YOUR WORKSPACE</span>
        <nav aria-label="Main navigation">
          <.link navigate={~p"/"} class={@active == "calendar" && "nav-active"}><.icon
            name="hero-calendar-days"
            class="size-5"
          />Calendar</.link>
          <.link navigate={~p"/library"} class={@active == "library" && "nav-active"}><.icon
            name="hero-book-open"
            class="size-5"
          />Library</.link>
          <.link navigate={~p"/studios"} class={@active == "studios" && "nav-active"}><.icon
            name="hero-building-storefront"
            class="size-5"
          />Studios</.link>
        </nav>
        <div class="sidebar-note">
          <span class="tiny-flower" aria-hidden="true">✳</span><p>
            A little planning.<br />A world of possibility.
          </p>
        </div>
        <.link href={~p"/sign-out"} method="delete" id="sign-out" class="sign-out">Sign out</.link>
      </aside>
      <main class="planner-main">
        <header class="planner-heading">
          <div>
            <span class="eyebrow">YOUR PRIVATE TEACHING SPACE</span><h1>
              {@title}<span class="brand-dot">.</span>
            </h1>
          </div>
        </header>
        <p id="unsaved-status" class="save-status" aria-live="polite" phx-update="ignore">
          Save each form when you're ready. Add, move and delete apply immediately.
        </p>
        {render_slot(@inner_block)}
        <footer class="planner-footer">
          <span>PLAN WITH INTENTION. TEACH WITH HEART.</span><span>Choreocal · Your private planner</span>
        </footer>
      </main>
    </div>
    """
  end

  def local_time(datetime, timezone),
    do: DateTime.shift_zone!(datetime, timezone, Tzdata.TimeZoneDatabase)

  def class_date(class), do: class.starts_at |> local_time(class.timezone) |> DateTime.to_date()

  def when_class(class),
    do: Calendar.strftime(local_time(class.starts_at, class.timezone), "%b %-d, %Y · %H:%M %Z")

  def error_message(%{errors: errors}) do
    errors
    |> Enum.map(fn error ->
      field = Map.get(error, :field)
      message = Map.get(error, :message)

      if field && is_binary(message),
        do: "#{field}: #{message}",
        else: "Check your entries; this change could not be saved."
    end)
    |> Enum.uniq()
    |> Enum.join(" ")
  end

  def error_message(_), do: "This change could not be saved. Refresh and try again."
end
