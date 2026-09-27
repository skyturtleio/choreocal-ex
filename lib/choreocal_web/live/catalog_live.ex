defmodule ChoreocalWeb.CatalogLive do
  use ChoreocalWeb, :live_view
  import ChoreocalWeb.PlannerComponents
  alias Choreocal.Planning

  def mount(_, _, socket),
    do: {:ok, assign(socket, editing: nil, draft: %{}, search: "", category: "", error: nil)}

  def handle_params(_, _, socket) do
    {:noreply,
     socket
     |> assign(
       page_title:
         if(socket.assigns.live_action == :studios, do: "Studios", else: "Exercise library")
     )
     |> refresh()}
  end

  defp refresh(socket) do
    opts = [actor: socket.assigns.current_user, query: [sort: [name: :asc]]]

    rows =
      if socket.assigns.live_action == :studios,
        do: Planning.list_studios!(opts),
        else: Planning.list_exercises!(Keyword.put(opts, :load, uses: [section: :class]))

    assign(socket, rows: rows)
  end

  def handle_event("filter", params, socket),
    do:
      {:noreply,
       assign(socket, search: params["search"] || "", category: params["category"] || "")}

  def handle_event("edit", %{"id" => id}, socket) do
    row = Enum.find(socket.assigns.rows, &(&1.id == id))

    draft =
      Map.new([:name, :address, :category, :cues], &{to_string(&1), Map.get(row || %{}, &1)})

    {:noreply, assign(socket, editing: row, draft: draft, error: nil)}
  end

  def handle_event("draft", %{"record" => attrs}, socket),
    do: {:noreply, assign(socket, draft: attrs)}

  def handle_event("cancel", _, socket),
    do: {:noreply, assign(socket, editing: nil, draft: %{}, error: nil)}

  def handle_event("save", %{"record" => attrs}, socket) do
    opts = [actor: socket.assigns.current_user]

    result =
      case {socket.assigns.live_action, socket.assigns.editing} do
        {:studios, nil} -> Planning.create_studio(attrs, opts)
        {:studios, row} -> Planning.update_studio(row, attrs, opts)
        {_, nil} -> Planning.create_exercise(attrs, opts)
        {_, row} -> Planning.update_exercise(row, attrs, opts)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(editing: nil, draft: %{}, error: nil)
         |> refresh()
         |> push_event("form-saved", %{id: "catalog-form"})}

      {:error, error} ->
        {:noreply, assign(socket, draft: attrs, error: error_message(error))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.rows, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      row ->
        result =
          if socket.assigns.live_action == :studios,
            do: Planning.destroy_studio(row, actor: socket.assigns.current_user),
            else: Planning.destroy_exercise(row, actor: socket.assigns.current_user)

        case result do
          :ok ->
            {:noreply,
             socket
             |> assign(editing: nil, draft: %{})
             |> refresh()
             |> put_flash(:info, "Deleted. Saved class plans are unchanged.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not delete this entry.")}
        end
    end
  end

  defp visible(rows, search, category) do
    Enum.filter(rows, fn row ->
      String.contains?(String.downcase(row.name), String.downcase(search)) &&
        (category == "" || Map.get(row, :category) == category)
    end)
  end

  defp uses(row),
    do:
      row.uses
      |> Enum.map(& &1.section.class)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.starts_at, {:desc, DateTime})

  defp last_taught(row),
    do: Enum.find(uses(row), &(DateTime.compare(&1.ends_at, DateTime.utc_now()) != :gt))

  def render(assigns) do
    assigns = assign(assigns, form: to_form(assigns.draft, as: :record))

    ~H"""
    <Layouts.app flash={@flash}>
      <.workspace
        title={@page_title}
        active={if @live_action == :studios, do: "studios", else: "library"}
      >
        <div class="catalog-layout">
          <section class="paper-card catalog-editor">
            <h2>
              {if @editing,
                do: "Edit entry",
                else: if(@live_action == :studios, do: "Add a studio", else: "Add an exercise")}
            </h2>
            <p class="muted">
              {if @live_action == :studios,
                do: "The places you teach.",
                else: "Reusable ideas. Editing the library never changes a saved class."}
            </p>
            <p :if={@error} role="alert" class="form-error">{@error}</p>
            <.form
              for={@form}
              id="catalog-form"
              phx-submit="save"
              phx-change="draft"
            >
              <.input
                field={@form[:name]}
                id="record-name"
                label="Name"
                required
                maxlength="200"
              />
              <.input
                :if={@live_action == :studios}
                field={@form[:address]}
                id="record-address"
                label="Address (optional)"
                type="textarea"
                rows="3"
              />
              <.input
                :if={@live_action == :library}
                field={@form[:category]}
                id="record-category"
                label="Category"
                required
                placeholder="Thighs, Seat, Core…"
              />
              <.input
                :if={@live_action == :library}
                field={@form[:cues]}
                id="record-cues"
                label="Cues / shorthand"
                type="textarea"
                rows="4"
              />
              <div class="form-actions">
                <button class="primary-button" phx-disable-with="Saving…">Save {if @live_action ==
                                                                                       :studios,
                                                                                     do: "studio",
                                                                                     else: "exercise"}</button><button
                  :if={@editing}
                  type="button"
                  phx-click="cancel"
                  data-mutates
                  class="quiet-button"
                >Cancel</button>
              </div>
            </.form>
          </section>
          <section class="catalog-list">
            <form id="catalog-filter" phx-change="filter" class="filter-bar">
              <.input
                name="search"
                id="catalog-search"
                type="search"
                value={@search}
                label="Find by name"
                placeholder="Search your workspace…"
              />
              <.input
                :if={@live_action == :library}
                name="category"
                id="category-filter"
                label="Category"
                type="select"
                value={@category}
                options={[
                  {"All categories", ""}
                  | Enum.map(Enum.sort(Enum.uniq(Enum.map(@rows, & &1.category))), &{&1, &1})
                ]}
              />
            </form>
            <p :if={visible(@rows, @search, @category) == []} class="empty-card">
              No entries yet. Add one to get started, or adjust your search.
            </p>
            <article
              :for={row <- visible(@rows, @search, @category)}
              class="paper-card library-entry"
              id={"entry-#{row.id}"}
            >
              <div class="row-heading">
                <div>
                  <span :if={@live_action == :library} class="eyebrow">{row.category}</span><h2>
                    {row.name}
                  </h2>
                </div><div class="row-actions">
                  <button phx-click="edit" phx-value-id={row.id} data-mutates class="quiet-button">Edit</button><button
                    phx-click="delete"
                    phx-value-id={row.id}
                    data-mutates
                    data-confirm="Delete this entry? Existing class plans keep their names and cues."
                    class="danger-button"
                  >Delete</button>
                </div>
              </div>
              <p class="preserve-lines muted">
                {if @live_action == :studios, do: row.address, else: row.cues}
              </p>
              <div :if={@live_action == :library} class="usage-history">
                <p class="muted">
                  {if last_taught(row),
                    do: "Last taught · #{when_class(last_taught(row))}",
                    else: "Not taught yet"}
                </p>
                <details>
                  <summary>Usage history · {length(uses(row))} classes</summary><p
                    :if={uses(row) == []}
                    class="muted"
                  >
                    Add this exercise to a class to start its history.
                  </p><.link
                    :for={class <- uses(row)}
                    navigate={~p"/classes/#{class.id}"}
                    class="history-link"
                  >{class.name} · {when_class(class)}</.link>
                </details>
              </div>
            </article>
          </section>
        </div>
      </.workspace>
    </Layouts.app>
    """
  end
end
