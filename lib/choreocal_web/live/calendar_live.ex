defmodule ChoreocalWeb.CalendarLive do
  use ChoreocalWeb, :live_view
  import ChoreocalWeb.PlannerComponents
  alias Choreocal.Planning

  def mount(_, _, socket) do
    today = Planning.today()

    {:ok,
     socket
     |> assign(
       page_title: "Your calendar",
       month: Date.beginning_of_month(today),
       today: today,
       selected: today,
       tab: "upcoming"
     )
     |> refresh()}
  end

  defp refresh(socket) do
    assign(socket,
      classes:
        Planning.list_classes!(
          actor: socket.assigns.current_user,
          query: [sort: [starts_at: :asc]],
          load: :studio
        ),
      imported: Planning.list_imports!(actor: socket.assigns.current_user) != []
    )
  end

  def handle_event("month", %{"direction" => direction}, socket)
      when direction in ["previous", "next"] do
    month = socket.assigns.month

    next =
      if direction == "next",
        do: Date.add(Date.end_of_month(month), 1),
        else: Date.beginning_of_month(Date.add(month, -1))

    {:noreply, assign(socket, month: next)}
  end

  def handle_event("today", _, socket),
    do:
      {:noreply,
       assign(socket,
         month: Date.beginning_of_month(socket.assigns.today),
         selected: socket.assigns.today
       )}

  def handle_event("select", %{"date" => date}, socket) do
    case Date.from_iso8601(date) do
      {:ok, selected} -> {:noreply, assign(socket, selected: selected)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("tab", %{"tab" => tab}, socket) when tab in ["upcoming", "past"],
    do: {:noreply, assign(socket, tab: tab)}

  def handle_event("import", _, socket) do
    case Planning.import_examples(%{}, actor: socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> refresh()
         |> assign(month: ~D[2026-09-01], selected: ~D[2026-09-19], tab: "past")
         |> put_flash(
           :info,
           "Three editable plans and their exercises imported. Open any class to make it yours."
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> refresh()
         |> put_flash(
           :error,
           "Examples were already imported, or the import could not complete. No partial import was saved."
         )}
    end
  end

  defp days(month) do
    start = Date.add(month, -rem(Date.day_of_week(month), 7))
    for offset <- 0..41, do: Date.add(start, offset)
  end

  defp on_date(classes, day), do: Enum.filter(classes, &(class_date(&1) == day))

  defp agenda(classes, tab) do
    rows =
      Enum.filter(classes, fn class ->
        DateTime.compare(class.ends_at, DateTime.utc_now()) == :lt == (tab == "past")
      end)

    if tab == "past", do: Enum.reverse(rows), else: rows
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.workspace title="Your calendar">
        <div class="calendar-page-actions">
          <p class="muted">Classes appear on their local date. Today uses New York time.</p><.link
            navigate={~p"/classes/new?#{[date: Date.to_iso8601(@selected)]}"}
            class="primary-button"
          >+ New class</.link>
        </div>
        <div class="planner-content">
          <section class="calendar-panel" aria-label="Monthly calendar">
            <div class="calendar-toolbar">
              <h2 id="calendar-month">{Calendar.strftime(@month, "%B %Y")}</h2><div class="calendar-controls">
                <button id="today" phx-click="today" class="quiet-button">Today</button><button
                  id="previous-month"
                  phx-click="month"
                  phx-value-direction="previous"
                  class="icon-button"
                  aria-label="Previous month"
                ><.icon name="hero-chevron-left" class="size-4" /></button><button
                  id="next-month"
                  phx-click="month"
                  phx-value-direction="next"
                  class="icon-button"
                  aria-label="Next month"
                ><.icon name="hero-chevron-right" class="size-4" /></button>
              </div>
            </div>
            <div class="calendar-weekdays">
              <span :for={day <- ~w(Sun Mon Tue Wed Thu Fri Sat)}>{day}</span>
            </div>
            <div class="calendar-grid" id="calendar-grid">
              <div
                :for={day <- days(@month)}
                class={[
                  "calendar-cell",
                  day.month != @month.month && "outside-month",
                  day == @today && "is-today",
                  day == @selected && "is-selected"
                ]}
              >
                <button
                  id={"day-#{day}"}
                  phx-click="select"
                  phx-value-date={day}
                  aria-label={Calendar.strftime(day, "%B %-d, %Y")}
                  aria-pressed={to_string(day == @selected)}
                  class="calendar-date"
                >{day.day}</button>
                <.link
                  :for={class <- on_date(@classes, day)}
                  navigate={~p"/classes/#{class.id}"}
                  class="calendar-class"
                  title={"#{class.name} · #{when_class(class)}"}
                >{Calendar.strftime(local_time(class.starts_at, class.timezone), "%H:%M")}
                <span>{class.name}</span></.link>
              </div>
            </div>
            <footer class="calendar-footer">
              <span class="legend-dot"></span>Select a day to plan. Open a class to edit.
            </footer>
          </section>
          <aside class="day-panel">
            <span class="eyebrow">IN FOCUS</span><h2 id="selected-date">
              {Calendar.strftime(@selected, "%A, %B %-d")}
            </h2>
            <p :if={on_date(@classes, @selected) == []} class="empty-card">
              No classes planned for this day.
            </p>
            <.class_card :for={class <- on_date(@classes, @selected)} class={class} />
            <.link
              navigate={~p"/classes/new?#{[date: Date.to_iso8601(@selected)]}"}
              class="quiet-button block-link"
            >+ Plan this day</.link>
          </aside>
        </div>
        <section class="agenda">
          <div class="row-heading">
            <h2>Your classes</h2><div class="tabs" role="group" aria-label="Class timeline">
              <button
                :for={tab <- ["upcoming", "past"]}
                phx-click="tab"
                phx-value-tab={tab}
                aria-pressed={to_string(@tab == tab)}
                class={@tab == tab && "active"}
              >{String.capitalize(tab)}</button>
            </div>
          </div>
          <p :if={agenda(@classes, @tab) == []} class="empty-card">No {@tab} classes yet.</p><div class="agenda-grid">
            <.class_card :for={class <- agenda(@classes, @tab)} class={class} />
          </div>
        </section>
        <section :if={!@imported} class="starter-import paper-card">
          <div>
            <span class="eyebrow">BRING YOUR PLANS WITH YOU</span><h2>Your three starter plans</h2><p class="muted">
              Import the May 29 exhale and July 11 / September 19 tyr examples, plus their exercises. Original shorthand and New York times, fully editable. Runs once, only when you choose.
            </p>
          </div><button
            id="import-examples"
            phx-click="import"
            data-confirm="Import the three example classes, two studios and their exercises into your private workspace? This can run only once."
            class="quiet-button"
            phx-disable-with="Importing…"
          >Import example plans</button>
        </section>
      </.workspace>
    </Layouts.app>
    """
  end

  attr :class, :map, required: true

  defp class_card(assigns) do
    ~H"""
    <.link navigate={~p"/classes/#{@class.id}"} class="class-card"><span class="eyebrow">{when_class(
      @class
    )}</span><h3>{@class.name}</h3><p class="muted">
      {if @class.studio, do: @class.studio.name, else: "No studio"}
    </p><span :if={@class.playlist_name} class="playlist-caption">♫ {@class.playlist_name}</span></.link>
    """
  end
end
