defmodule ChoreocalWeb.CalendarLive do
  use ChoreocalWeb, :live_view

  def mount(_, _, socket) do
    today = Choreocal.Planning.today()

    {:ok,
     assign(socket,
       page_title: "Your calendar",
       month: Date.beginning_of_month(today),
       today: today,
       selected: today
     )}
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

  defp days(month) do
    start = Date.add(month, -rem(Date.day_of_week(month), 7))
    for offset <- 0..41, do: Date.add(start, offset)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="planner-shell">
        <aside class="planner-sidebar">
          <a href={~p"/"} class="wordmark">choreocal<span class="brand-dot">.</span></a>
          <span class="eyebrow sidebar-label">YOUR WORKSPACE</span>
          <nav aria-label="Main navigation">
            <a class="nav-active" href={~p"/"}><.icon name="hero-calendar-days" class="size-5" />Calendar</a>
          </nav>
          <div class="sidebar-note">
            <span class="tiny-flower" aria-hidden="true">✳</span><p>
              A little planning.<br />A world of possibility.
            </p>
          </div>
          <.link href={~p"/sign-out"} method="delete" id="sign-out" class="sign-out"><.icon
            name="hero-arrow-left-on-rectangle"
            class="size-4"
          />Sign out</.link>
        </aside>
        <main class="planner-main">
          <header class="planner-heading">
            <div>
              <span class="eyebrow">MAKE SPACE FOR WHAT MOVES YOU</span><h1>
                Your calendar<span class="brand-dot">.</span>
              </h1><p class="muted">A clear view of the days ahead.</p>
            </div><span class="private-badge"><.icon name="hero-lock-closed" class="size-3.5" />Private workspace</span>
          </header>
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
                <button
                  :for={day <- days(@month)}
                  id={"day-#{day}"}
                  phx-click="select"
                  phx-value-date={day}
                  aria-label={Calendar.strftime(day, "%B %-d, %Y")}
                  aria-pressed={to_string(day == @selected)}
                  class={[
                    "calendar-day",
                    day.month != @month.month && "outside-month",
                    day == @today && "is-today",
                    day == @selected && "is-selected"
                  ]}
                ><span>{day.day}</span><span :if={day == @today} class="today-label">Today</span></button>
              </div>
              <footer class="calendar-footer">
                <span class="legend-dot"></span> Your month, with room to grow.
              </footer>
            </section>
            <aside class="day-panel">
              <span class="eyebrow">IN FOCUS</span><h2 id="selected-date">
                {Calendar.strftime(@selected, "%A, %B %-d")}
              </h2><div class="empty-day">
                <span class="empty-icon"><.icon name="hero-sun" class="size-8" /></span><h3>
                  A little breathing room.
                </h3><p>No classes planned for this day.</p>
              </div><div class="foundation-note">
                <span class="eyebrow">THE FIRST STEP</span><h3>Your teaching space is ready.</h3><p>
                  Secure access and your calendar are in place. Class planning and your exercise library are coming next.
                </p>
              </div>
            </aside>
          </div>
          <footer class="planner-footer">
            <span>PLAN WITH INTENTION. TEACH WITH HEART.</span><span>Choreocal · Your private planner</span>
          </footer>
        </main>
      </div>
    </Layouts.app>
    """
  end
end
