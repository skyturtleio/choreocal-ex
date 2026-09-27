defmodule ChoreocalWeb.PlannerLiveTest do
  use ChoreocalWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Choreocal.Planning, as: P

  setup %{conn: conn} do
    :sys.replace_state(Choreocal.AuthRateLimit, fn _ -> %{} end)

    actor =
      Choreocal.Accounts.User
      |> Ash.Changeset.for_create(:provision, %{
        email: "flow@example.test",
        hashed_password: Bcrypt.hash_pwd_salt("test-only-planner-passphrase")
      })
      |> Ash.create!(authorize?: false)

    conn =
      post(conn, ~p"/sign-in",
        user: %{email: "flow@example.test", password: "test-only-planner-passphrase"}
      )

    %{conn: conn, actor: actor, opts: [actor: actor]}
  end

  test "studio and library CRUD through forms, category filter and historical usage", %{
    conn: conn,
    opts: opts
  } do
    {:ok, view, _} = live(conn, ~p"/studios")

    view
    |> form("#catalog-form", record: %{name: "Riverside", address: "12 West St"})
    |> render_submit()

    [studio] = P.list_studios!(opts)
    assert has_element?(view, "#entry-#{studio.id}", "Riverside")
    view |> element("#entry-#{studio.id} button", "Edit") |> render_click()

    view
    |> form("#catalog-form",
      record: %{name: "Riverside upstairs", address: "12 West St, Floor 2"}
    )
    |> render_submit()

    assert P.get_studio!(studio.id, opts).address == "12 West St, Floor 2"
    {:ok, library_view, _} = live(conn, ~p"/library")

    library_view
    |> form("#catalog-form", record: %{name: "Chair", category: "Thighs", cues: "d2u2, tempo"})
    |> render_submit()

    [exercise] = P.list_exercises!(opts)
    assert has_element?(library_view, "#entry-#{exercise.id}", "Not taught yet")
    library_view |> form("#catalog-filter", search: "not present") |> render_change()
    refute has_element?(library_view, "#entry-#{exercise.id}")
    library_view |> form("#catalog-filter", search: "", category: "Thighs") |> render_change()
    assert has_element?(library_view, "#entry-#{exercise.id}", "Chair")
    library_view |> element("#entry-#{exercise.id} button", "Edit") |> render_click()

    library_view
    |> form("#catalog-form", record: %{name: "Wide chair", category: "Seat", cues: "lift hold"})
    |> render_submit()

    assert P.get_exercise!(exercise.id, opts).category == "Seat"
    library_view |> form("#catalog-filter", search: "", category: "") |> render_change()
    library_view |> element("#entry-#{exercise.id} button", "Delete") |> render_click()
    assert P.list_exercises!(opts) == []
    view |> element("#entry-#{studio.id} button", "Delete") |> render_click()
    assert P.list_studios!(opts) == []
  end

  test "create, reopen, edit, reorder, duplicate across DST, library history and delete", %{
    conn: conn,
    opts: opts
  } do
    studio = P.create_studio!(%{name: "Studio A"}, opts)
    library = P.create_exercise!(%{name: "Chair", category: "Thighs", cues: "d2u2"}, opts)
    {:ok, view, _} = live(conn, ~p"/classes/new?date=2026-07-14")

    view
    |> form("#class-form",
      class: %{
        name: "Late barre",
        studio_id: studio.id,
        starts_at: "2026-07-14T23:30",
        ends_at: "2026-07-15T00:25",
        timezone: "America/New_York",
        playlist_name: "exhale 4",
        playlist_url: "https://open.spotify.com/playlist/example"
      }
    )
    |> render_submit()

    [class] = P.list_classes!(opts)
    assert class.starts_at == ~U[2026-07-15 03:30:00Z]
    assert_redirect(view, ~p"/classes/#{class.id}")
    {:ok, view, _} = live(conn, ~p"/classes/#{class.id}")

    for name <- ["Thighs", "Core", "Seat"] do
      view |> form("#new-section-form", section: %{name: name}) |> render_submit()
    end

    [thighs, core, seat] = P.get_class!(class.id, Keyword.put(opts, :load, :sections)).sections
    assert has_element?(view, "#add-exercise-details-#{thighs.id}[phx-mounted*='ignore_attrs']")
    assert has_element?(view, "#rename-section-#{thighs.id}[phx-mounted*='ignore_attrs']")
    view |> element("button[aria-label='Move Seat up']") |> render_click()

    assert Enum.map(
             P.get_class!(class.id, Keyword.put(opts, :load, :sections)).sections,
             & &1.name
           ) == ["Thighs", "Seat", "Core"]

    view |> form("#section-form-#{seat.id}", section: %{name: "Glutes"}) |> render_submit()

    view
    |> form("#library-form-#{thighs.id}", library: %{exercise_id: library.id})
    |> render_submit()

    view
    |> form("#add-exercise-#{thighs.id}", exercise: %{name: "Second move", cues: "pulse"})
    |> render_submit()

    [chair, second] =
      hd(P.get_class!(class.id, Keyword.put(opts, :load, sections: :exercises)).sections).exercises

    view |> element("button[aria-label='Move Second move up']") |> render_click()

    view
    |> form("#exercise-form-#{chair.id}",
      exercise: %{name: "Chair snapshot", cues: "Original class cue"}
    )
    |> render_submit()

    {:ok, reopened, _} = live(conn, ~p"/classes/#{class.id}")
    assert has_element?(reopened, "#exercise-name-#{chair.id}[value='Chair snapshot']")
    assert has_element?(reopened, "#edit-exercise-#{chair.id}[phx-mounted*='ignore_attrs']")
    assert P.get_exercise!(library.id, opts).name == "Chair"
    {:ok, calendar, _} = live(conn, ~p"/")
    calendar |> element("button[phx-value-tab=past]") |> render_click()
    assert has_element?(calendar, "a[href='/classes/#{class.id}']", "Late barre")
    {:ok, history, _} = live(conn, ~p"/library")
    assert has_element?(history, "#entry-#{library.id}", "Last taught")
    assert has_element?(history, "a[href='/classes/#{class.id}']", "Jul 14, 2026 · 23:30 EDT")
    reopened |> form("#duplicate-form", copy: %{date: "2026-12-14"}) |> render_submit()
    copy = P.list_classes!(opts) |> Enum.find(&(&1.id != class.id))
    assert copy.starts_at == ~U[2026-12-15 04:30:00Z]
    assert copy.ends_at == ~U[2026-12-15 05:25:00Z]
    {:ok, copy_view, _} = live(conn, ~p"/classes/#{copy.id}")
    copy_loaded = P.get_class!(copy.id, Keyword.put(opts, :load, sections: :exercises))
    assert Enum.map(copy_loaded.sections, & &1.name) == ["Thighs", "Glutes", "Core"]

    assert Enum.map(hd(copy_loaded.sections).exercises, & &1.name) == [
             "Second move",
             "Chair snapshot"
           ]

    copy_view |> element("button[phx-click=delete-class]") |> render_click()
    assert length(P.list_classes!(opts)) == 1

    view
    |> element("button[phx-click=delete-exercise][phx-value-id='#{second.id}']")
    |> render_click()

    view
    |> element("button[phx-click=delete-section][phx-value-id='#{core.id}']")
    |> render_click()

    assert length(P.get_class!(class.id, Keyword.put(opts, :load, :sections)).sections) == 2
  end

  test "visible DST validation and authenticated one-shot example import", %{
    conn: conn,
    opts: opts
  } do
    {:ok, view, _} = live(conn, ~p"/classes/new")

    view
    |> form("#class-form",
      class: %{name: "Gap", starts_at: "2026-03-08T02:30", ends_at: "2026-03-08T03:30"}
    )
    |> render_submit()

    assert has_element?(view, "[role=alert]", "daylight saving")
    assert P.list_classes!(opts) == []
    {:ok, calendar, _} = live(conn, ~p"/")
    calendar |> element("#import-examples") |> render_click()
    assert length(P.list_classes!(opts)) == 3
    refute has_element?(calendar, "#import-examples")
    assert has_element?(calendar, "#calendar-month", "September 2026")
    assert has_element?(calendar, ".calendar-class", "tyr")
    assert has_element?(calendar, "#selected-date", "Saturday, September 19")
  end

  test "all new screens require authentication", %{conn: _} do
    for path <- ["/studios", "/library", "/classes/new", "/classes/#{Ash.UUID.generate()}"] do
      assert redirected_to(get(build_conn(), path)) == "/sign-in"
    end
  end
end
