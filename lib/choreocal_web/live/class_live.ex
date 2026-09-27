defmodule ChoreocalWeb.ClassLive do
  use ChoreocalWeb, :live_view
  import ChoreocalWeb.PlannerComponents
  alias Choreocal.Planning

  def mount(_, _, socket), do: {:ok, assign(socket, error: nil, class: nil)}

  def handle_params(params, _, socket) do
    opts = [actor: socket.assigns.current_user]

    socket =
      assign(socket,
        studios: Planning.list_studios!(opts),
        library:
          Planning.list_exercises!(Keyword.put(opts, :query, sort: [category: :asc, name: :asc]))
      )

    if socket.assigns.live_action == :new do
      date =
        case Date.from_iso8601(params["date"] || "") do
          {:ok, date} -> date
          _ -> Date.utc_today()
        end

      {:noreply,
       assign(socket,
         page_title: "New class",
         details: %{
           "timezone" => "America/New_York",
           "starts_at" => "#{date}T11:30",
           "ends_at" => "#{date}T12:25"
         }
       )}
    else
      case Planning.get_class(
             params["id"],
             Keyword.put(opts, :load, [:studio, sections: :exercises])
           ) do
        {:ok, class} when not is_nil(class) ->
          {:noreply, load_class(socket, class)}

        _ ->
          {:noreply, socket |> put_flash(:error, "Class not found.") |> push_navigate(to: ~p"/")}
      end
    end
  end

  defp load_class(socket, class) do
    details =
      Map.new(
        [:name, :studio_id, :playlist_name, :playlist_url, :timezone],
        &{to_string(&1), Map.get(class, &1)}
      )

    details =
      Enum.reduce([:starts_at, :ends_at], details, fn field, acc ->
        Map.put(
          acc,
          to_string(field),
          Calendar.strftime(local_time(Map.get(class, field), class.timezone), "%Y-%m-%dT%H:%M")
        )
      end)

    assign(socket, class: class, details: details, page_title: class.name, error: nil)
  end

  defp refresh(socket),
    do:
      load_class(
        socket,
        Planning.get_class!(socket.assigns.class.id,
          actor: socket.assigns.current_user,
          load: [:studio, sections: :exercises]
        )
      )

  @doc "Reject DST gaps and ambiguous clock times rather than silently scheduling a different instant."
  def schedule(attrs) do
    with true <- is_binary(attrs["timezone"]),
         {:ok, start_naive} <- NaiveDateTime.from_iso8601((attrs["starts_at"] || "") <> ":00"),
         {:ok, end_naive} <- NaiveDateTime.from_iso8601((attrs["ends_at"] || "") <> ":00"),
         {:ok, start} <-
           DateTime.from_naive(start_naive, attrs["timezone"], Tzdata.TimeZoneDatabase),
         {:ok, finish} <-
           DateTime.from_naive(end_naive, attrs["timezone"], Tzdata.TimeZoneDatabase) do
      {:ok, attrs |> Map.put("starts_at", start) |> Map.put("ends_at", finish)}
    else
      _ ->
        {:error,
         "Choose valid start/end times and an IANA timezone. Times skipped or repeated by daylight saving are not accepted."}
    end
  end

  def handle_event("save-class", %{"class" => attrs}, socket) do
    result =
      with {:ok, attrs} <- schedule(attrs) do
        if socket.assigns.class,
          do:
            Planning.update_class(socket.assigns.class, attrs, actor: socket.assigns.current_user),
          else: Planning.create_class(attrs, actor: socket.assigns.current_user)
      end

    case result do
      {:ok, class} ->
        socket =
          socket
          |> push_event("form-saved", %{id: "class-form"})

        if socket.assigns.class,
          do: {:noreply, refresh(socket)},
          else: {:noreply, push_navigate(socket, to: ~p"/classes/#{class.id}")}

      {:error, error} ->
        {:noreply,
         assign(socket,
           details: attrs,
           error: if(is_binary(error), do: error, else: error_message(error))
         )}
    end
  end

  def handle_event("duplicate", %{"copy" => %{"date" => date}}, socket) do
    class = socket.assigns.class
    start = local_time(class.starts_at, class.timezone)

    with {:ok, date} <- Date.from_iso8601(date),
         {:ok, naive} <- NaiveDateTime.new(date, DateTime.to_time(start)),
         {:ok, start} <- DateTime.from_naive(naive, class.timezone, Tzdata.TimeZoneDatabase),
         {:ok, copy} <-
           Planning.duplicate_class(
             %{
               source_id: class.id,
               starts_at: start,
               ends_at:
                 DateTime.add(
                   start,
                   DateTime.diff(class.ends_at, class.starts_at),
                   :second,
                   Tzdata.TimeZoneDatabase
                 ),
               timezone: class.timezone
             },
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> push_event("form-saved", %{id: "duplicate-form"})
       |> put_flash(:info, "Independent copy created. The original is unchanged.")
       |> push_navigate(to: ~p"/classes/#{copy.id}")}
    else
      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not duplicate. Choose a valid date and unambiguous local time."
         )}
    end
  end

  def handle_event("delete-class", _, socket) do
    case Planning.destroy_class(socket.assigns.class, actor: socket.assigns.current_user) do
      :ok -> {:noreply, socket |> put_flash(:info, "Class deleted.") |> push_navigate(to: ~p"/")}
      _ -> {:noreply, put_flash(socket, :error, "Could not delete this class.")}
    end
  end

  def handle_event("add-section", %{"section" => attrs}, socket) do
    attrs =
      Map.merge(attrs, %{
        "class_id" => socket.assigns.class.id,
        "position" => next_position(socket.assigns.class.sections)
      })

    saved(
      socket,
      Planning.create_section(attrs, actor: socket.assigns.current_user),
      "new-section-form"
    )
  end

  def handle_event("save-section", %{"section" => %{"id" => id} = attrs}, socket) do
    with %{} = section <- find_section(socket, id) do
      saved(
        socket,
        Planning.update_section(section, Map.take(attrs, ["name"]),
          actor: socket.assigns.current_user
        ),
        "section-form-#{id}"
      )
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete-section", %{"id" => id}, socket) do
    with %{} = section <- find_section(socket, id) do
      saved(
        socket,
        Planning.destroy_section(section, actor: socket.assigns.current_user),
        "section-form-#{id}"
      )
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("add-exercise", %{"exercise" => %{"section_id" => id} = attrs}, socket) do
    with %{} = section <- find_section(socket, id) do
      attrs = Map.put(attrs, "position", next_position(section.exercises))

      saved(
        socket,
        Planning.create_class_exercise(attrs, actor: socket.assigns.current_user),
        "add-exercise-#{id}"
      )
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(
        "add-library",
        %{"library" => %{"section_id" => id, "exercise_id" => exercise_id}},
        socket
      ) do
    with %{} = section <- find_section(socket, id) do
      saved(
        socket,
        Planning.create_class_exercise(
          %{section_id: id, exercise_id: exercise_id, position: next_position(section.exercises)},
          actor: socket.assigns.current_user
        ),
        "library-form-#{id}"
      )
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("save-exercise", %{"exercise" => %{"id" => id} = attrs}, socket) do
    with %{} = exercise <- find_exercise(socket, id) do
      saved(
        socket,
        Planning.update_class_exercise(exercise, Map.take(attrs, ["name", "cues"]),
          actor: socket.assigns.current_user
        ),
        "exercise-form-#{id}"
      )
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete-exercise", %{"id" => id}, socket) do
    with %{} = exercise <- find_exercise(socket, id) do
      saved(
        socket,
        Planning.destroy_class_exercise(exercise, actor: socket.assigns.current_user),
        "exercise-form-#{id}"
      )
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("move", %{"id" => id, "direction" => direction} = params, socket)
      when direction in ["up", "down"] do
    section = params["section"] && find_section(socket, params["section"])
    rows = if section, do: section.exercises, else: socket.assigns.class.sections
    index = Enum.find_index(rows, &(&1.id == id))
    target = if index, do: index + if(direction == "up", do: -1, else: 1), else: -1

    if index && target >= 0 && target < length(rows) do
      ids = Enum.map(rows, & &1.id)
      ids = ids |> List.replace_at(index, Enum.at(ids, target)) |> List.replace_at(target, id)

      saved(
        socket,
        Planning.reorder(
          %{class_id: socket.assigns.class.id, section_id: section && section.id, ids: ids},
          actor: socket.assigns.current_user
        ),
        nil
      )
    else
      {:noreply, socket}
    end
  end

  defp find_section(socket, id), do: Enum.find(socket.assigns.class.sections, &(&1.id == id))

  defp find_exercise(socket, id),
    do:
      socket.assigns.class.sections |> Enum.flat_map(& &1.exercises) |> Enum.find(&(&1.id == id))

  defp next_position(rows), do: Enum.reduce(rows, 0, &max(&1.position + 1, &2))

  defp saved(socket, result, form) do
    case result do
      result when result == :ok or elem(result, 0) == :ok ->
        {:noreply,
         socket
         |> refresh()
         |> push_event("form-saved", %{id: form})}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def render(assigns) do
    sections = if assigns.class, do: assigns.class.sections, else: []

    assigns =
      assign(assigns,
        form: to_form(assigns.details, as: :class),
        section_forms: Map.new(sections, &{&1.id, record_form(&1, :section, [:id, :name])}),
        exercise_forms:
          Map.new(
            Enum.flat_map(sections, & &1.exercises),
            &{&1.id, record_form(&1, :exercise, [:id, :name, :cues])}
          ),
        new_exercise_forms:
          Map.new(sections, &{&1.id, to_form(%{"section_id" => &1.id}, as: :exercise)}),
        library_forms:
          Map.new(sections, &{&1.id, to_form(%{"section_id" => &1.id}, as: :library)}),
        new_section_form: to_form(%{}, as: :section),
        copy_form:
          to_form(%{"date" => assigns.class && Date.add(class_date(assigns.class), 7)}, as: :copy)
      )

    ~H"""
    <Layouts.app flash={@flash}>
      <.workspace title={@page_title}>
        <.link navigate={~p"/"} class="back-link">← Back to calendar</.link>
        <div class="class-layout">
          <section class="paper-card class-details">
            <h2>Class details</h2><p :if={@error} class="form-error" role="alert">{@error}</p>
            <div :if={@class} class="class-summary">
              <p class="eyebrow">
                {Calendar.strftime(local_time(@class.starts_at, @class.timezone), "%A, %B %-d")}
              </p>
              <p class="schedule-time">
                {Calendar.strftime(local_time(@class.starts_at, @class.timezone), "%H:%M")}–{Calendar.strftime(
                  local_time(@class.ends_at, @class.timezone),
                  "%H:%M %Z"
                )}
              </p>
              <p class="muted">{@class.timezone}</p>
              <p :if={@class.studio} class="summary-studio">{@class.studio.name}</p>
              <p :if={@class.playlist_name} class="playlist-caption">♫ {@class.playlist_name}</p>
            </div>
            <details
              id="edit-class-details"
              open={is_nil(@class) || not is_nil(@error)}
              phx-mounted={JS.ignore_attributes("open")}
            >
              <summary>{if @class, do: "Edit class details", else: "Schedule your class"}</summary>
              <.form for={@form} id="class-form" phx-submit="save-class">
                <.input
                  field={@form[:name]}
                  id="class-name"
                  label="Class name"
                  required
                  maxlength="200"
                />
                <.input
                  field={@form[:studio_id]}
                  id="class-studio"
                  label="Studio"
                  type="select"
                  options={[{"No studio", ""} | Enum.map(@studios, &{&1.name, &1.id})]}
                />
                <.link navigate={~p"/studios"} class="small-link">Manage studios</.link>
                <.input
                  field={@form[:starts_at]}
                  id="class-start"
                  label="Starts"
                  type="datetime-local"
                  required
                />
                <.input
                  field={@form[:ends_at]}
                  id="class-end"
                  label="Ends"
                  type="datetime-local"
                  required
                />
                <.input
                  field={@form[:timezone]}
                  id="class-timezone"
                  label="Timezone"
                  type="select"
                  options={Tzdata.zone_list()}
                />
                <.input
                  field={@form[:playlist_name]}
                  id="class-playlist"
                  label="Spotify playlist name"
                />
                <.input
                  field={@form[:playlist_url]}
                  id="class-playlist-url"
                  label="Spotify link (optional)"
                  type="url"
                  placeholder="https://open.spotify.com/playlist/…"
                />
                <button class="primary-button" phx-disable-with="Saving…">{if @class,
                  do: "Save details",
                  else: "Create class"}</button>
              </.form>
            </details>
            <div :if={@class} class="class-tools">
              <a
                :if={@class.playlist_url}
                href={@class.playlist_url}
                target="_blank"
                rel="noopener noreferrer"
                class="small-link"
              >Open Spotify ↗</a>
              <details id="duplicate-details" phx-mounted={JS.ignore_attributes("open")}>
                <summary>Duplicate to another date</summary><.form
                  for={@copy_form}
                  id="duplicate-form"
                  phx-submit="duplicate"
                >
                  <.input
                    field={@copy_form[:date]}
                    id="copy-date"
                    label="New date"
                    type="date"
                    required
                  /><p class="muted">
                    Copies the saved plan, local start time and duration. Future edits stay independent.
                  </p><button class="quiet-button" phx-disable-with="Copying…">Duplicate class</button>
                </.form>
              </details>
              <button
                phx-click="delete-class"
                data-mutates
                data-confirm="Delete this class and all of its sections and exercises?"
                class="danger-button"
              >Delete class</button>
            </div>
          </section>
          <section class="class-plan">
            <div class="row-heading">
              <div>
                <span class="eyebrow">THE FLOW</span><h2>Your class plan</h2>
              </div><span :if={@class} class="count-badge">{length(@class.sections)} sections</span>
            </div>
            <p :if={!@class} class="empty-card">
              Save your class details first. Then build its flow with sections and exercises.
            </p>
            <div :if={@class}>
              <p :if={@class.sections == []} class="empty-card">
                Start with a section — Thighs, Seat, Core, or any name that fits.
              </p>
              <article
                :for={{section, index} <- Enum.with_index(@class.sections)}
                id={"section-#{section.id}"}
                class="paper-card section-card"
              >
                <div class="row-heading">
                  <div class="section-title">
                    <span class="section-number">{index + 1}</span><h2>{section.name}</h2>
                  </div><div class="row-actions">
                    <.move_buttons
                      id={section.id}
                      index={index}
                      count={length(@class.sections)}
                      label={section.name}
                    /><button
                      phx-click="delete-section"
                      phx-value-id={section.id}
                      data-mutates
                      data-confirm="Delete this section and its exercises?"
                      class="danger-button"
                    >Delete section</button>
                  </div>
                </div>
                <details
                  id={"rename-section-#{section.id}"}
                  phx-mounted={JS.ignore_attributes("open")}
                >
                  <summary>Rename section</summary>
                  <.form
                    for={@section_forms[section.id]}
                    id={"section-form-#{section.id}"}
                    phx-submit="save-section"
                    class="inline-form"
                  >
                    <.input
                      field={@section_forms[section.id][:id]}
                      id={"section-id-#{section.id}"}
                      type="hidden"
                    /><.input
                      field={@section_forms[section.id][:name]}
                      id={"section-name-#{section.id}"}
                      label="Section name"
                      required
                    /><button class="quiet-button" phx-disable-with="Saving…">Save name</button>
                  </.form>
                </details>
                <div
                  :for={{exercise, ex_index} <- Enum.with_index(section.exercises)}
                  id={"exercise-#{exercise.id}"}
                  class="class-exercise"
                >
                  <div class="row-heading">
                    <span class="eyebrow">{if exercise.exercise_id,
                      do: "LIBRARY SNAPSHOT",
                      else: "CLASS-ONLY EXERCISE"}</span><div class="row-actions">
                      <.move_buttons
                        id={exercise.id}
                        section={section.id}
                        index={ex_index}
                        count={length(section.exercises)}
                        label={exercise.name}
                      /><button
                        phx-click="delete-exercise"
                        phx-value-id={exercise.id}
                        data-mutates
                        data-confirm="Remove this exercise from the class?"
                        class="danger-button"
                      >Remove</button>
                    </div>
                  </div>
                  <h3 class="exercise-title">{exercise.name}</h3>
                  <p class="preserve-lines exercise-cues">{exercise.cues}</p>
                  <details
                    id={"edit-exercise-#{exercise.id}"}
                    phx-mounted={JS.ignore_attributes("open")}
                  >
                    <summary>Edit exercise</summary>
                    <.form
                      for={@exercise_forms[exercise.id]}
                      id={"exercise-form-#{exercise.id}"}
                      phx-submit="save-exercise"
                    >
                      <.input
                        field={@exercise_forms[exercise.id][:id]}
                        id={"exercise-id-#{exercise.id}"}
                        type="hidden"
                      /><.input
                        field={@exercise_forms[exercise.id][:name]}
                        id={"exercise-name-#{exercise.id}"}
                        label="Exercise name"
                        required
                      /><.input
                        field={@exercise_forms[exercise.id][:cues]}
                        id={"exercise-cues-#{exercise.id}"}
                        label="Cues / shorthand"
                        type="textarea"
                        rows="2"
                      /><button class="quiet-button" phx-disable-with="Saving…">Save exercise</button>
                    </.form>
                  </details>
                </div>
                <details
                  id={"add-exercise-details-#{section.id}"}
                  class="add-exercise"
                  phx-mounted={JS.ignore_attributes("open")}
                >
                  <summary>+ Add an exercise</summary>
                  <.form
                    for={@new_exercise_forms[section.id]}
                    id={"add-exercise-#{section.id}"}
                    phx-submit="add-exercise"
                  >
                    <.input
                      field={@new_exercise_forms[section.id][:section_id]}
                      id={"new-exercise-section-#{section.id}"}
                      type="hidden"
                    /><.input
                      field={@new_exercise_forms[section.id][:name]}
                      id={"new-name-#{section.id}"}
                      label="New class-only exercise"
                      required
                    /><.input
                      field={@new_exercise_forms[section.id][:cues]}
                      id={"new-cues-#{section.id}"}
                      label="Cues / shorthand"
                      type="textarea"
                      rows="2"
                    /><button class="quiet-button" phx-disable-with="Adding…">Add exercise</button>
                  </.form>
                  <.form
                    :if={@library != []}
                    for={@library_forms[section.id]}
                    id={"library-form-#{section.id}"}
                    phx-submit="add-library"
                    class="library-picker"
                  >
                    <.input
                      field={@library_forms[section.id][:section_id]}
                      id={"library-section-#{section.id}"}
                      type="hidden"
                    /><.input
                      field={@library_forms[section.id][:exercise_id]}
                      id={"library-picker-#{section.id}"}
                      label="Or choose from your library"
                      type="select"
                      prompt="Select an exercise"
                      options={Enum.map(@library, &{"#{&1.category} · #{&1.name}", &1.id})}
                      required
                    /><button class="quiet-button" phx-disable-with="Adding…">Add from library</button>
                  </.form>
                  <p :if={@library == []} class="muted">
                    Your library is empty.
                    <.link navigate={~p"/library"} class="small-link">Add reusable exercises</.link>
                  </p>
                </details>
              </article>
              <.form
                for={@new_section_form}
                id="new-section-form"
                phx-submit="add-section"
                class="paper-card inline-form"
              >
                <.input
                  field={@new_section_form[:name]}
                  id="new-section-name"
                  label="New section"
                  placeholder="Thighs, Seat, Core…"
                  required
                /><button class="primary-button" phx-disable-with="Adding…">Add section</button>
              </.form>
            </div>
          </section>
        </div>
      </.workspace>
    </Layouts.app>
    """
  end

  defp record_form(record, as, fields),
    do: to_form(Map.new(fields, &{to_string(&1), Map.get(record, &1)}), as: as)

  attr :id, :string, required: true
  attr :section, :string, default: nil
  attr :index, :integer, required: true
  attr :count, :integer, required: true
  attr :label, :string, required: true

  defp move_buttons(assigns) do
    ~H"""
    <button
      :for={{direction, disabled} <- [{"up", @index == 0}, {"down", @index == @count - 1}]}
      phx-click="move"
      phx-value-id={@id}
      phx-value-section={@section}
      phx-value-direction={direction}
      data-mutates
      disabled={disabled}
      class="icon-button"
      aria-label={"Move #{@label} #{direction}"}
    ><.icon
      name={if direction == "up", do: "hero-chevron-up", else: "hero-chevron-down"}
      class="size-4"
    /></button>
    """
  end
end
