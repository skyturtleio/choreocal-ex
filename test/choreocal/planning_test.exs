defmodule Choreocal.PlanningTest do
  use Choreocal.DataCase
  alias Choreocal.Planning, as: P
  alias ChoreocalWeb.PlannerComponents, as: UI

  defp owner(email) do
    Choreocal.Accounts.User
    |> Ash.Changeset.for_create(:provision, %{email: email, hashed_password: "not-a-login-hash"})
    |> Ash.create!(authorize?: false)
  end

  setup do
    actor = owner("planner@example.test")
    %{actor: actor, opts: [actor: actor]}
  end

  defp class(opts, attrs \\ %{}) do
    P.create_class!(
      Map.merge(
        %{
          name: "Evening barre",
          starts_at: ~U[2026-07-15 03:30:00Z],
          ends_at: ~U[2026-07-15 04:25:00Z],
          timezone: "America/New_York"
        },
        attrs
      ),
      opts
    )
  end

  test "New York today and per-class dates use local dates across midnight" do
    assert P.today(~U[2026-07-15 03:59:59Z]) == ~D[2026-07-14]
    assert P.today(~U[2026-07-15 04:00:00Z]) == ~D[2026-07-15]
    assert P.today(~U[2026-01-15 04:59:59Z]) == ~D[2026-01-14]
    assert P.today(~U[2026-01-15 05:00:00Z]) == ~D[2026-01-15]

    assert UI.class_date(%{starts_at: ~U[2026-07-15 03:30:00Z], timezone: "America/New_York"}) ==
             ~D[2026-07-14]

    assert UI.class_date(%{starts_at: ~U[2026-07-15 03:30:00Z], timezone: "Europe/London"}) ==
             ~D[2026-07-15]
  end

  test "schedule rejects DST gaps and repeats, and converts explicit winter and summer local input" do
    for start <- ["2026-03-08T02:30", "2026-11-01T01:30"] do
      assert {:error, message} =
               ChoreocalWeb.ClassLive.schedule(%{
                 "starts_at" => start,
                 "ends_at" => "2026-11-01T03:30",
                 "timezone" => "America/New_York"
               })

      assert message =~ "daylight saving"
    end

    for {date, expected} <- [
          {"2026-07-15", ~U[2026-07-15 15:30:00Z]},
          {"2026-12-15", ~U[2026-12-15 16:30:00Z]}
        ] do
      assert {:ok, attrs} =
               ChoreocalWeb.ClassLive.schedule(%{
                 "starts_at" => "#{date}T11:30",
                 "ends_at" => "#{date}T12:25",
                 "timezone" => "America/New_York"
               })

      assert DateTime.compare(attrs["starts_at"], expected) == :eq
      assert DateTime.diff(attrs["ends_at"], attrs["starts_at"]) == 3300
    end
  end

  test "owner policies deny anonymous and cross-owner reads, writes, foreign links and operations",
       %{opts: opts} do
    foreign = [actor: owner("other@example.test")]
    studio = P.create_studio!(%{name: "Private studio"}, opts)
    exercise = P.create_exercise!(%{name: "Private exercise", category: "Seat"}, opts)
    class = class(opts, %{studio_id: studio.id})
    section = P.create_section!(%{class_id: class.id, name: "Seat"}, opts)
    row = P.create_class_exercise!(%{section_id: section.id, exercise_id: exercise.id}, opts)
    assert P.list_classes!(foreign) == []
    assert P.list_studios!(foreign) == []
    assert P.list_exercises!(foreign) == []

    for resource <- [
          P.Studio,
          P.Exercise,
          P.Class,
          P.ClassSection,
          P.ClassExercise,
          P.StarterImport
        ] do
      assert {:error, _} = resource |> Ash.Changeset.for_create(:create, %{}) |> Ash.create()
    end

    for record <- [studio, exercise, class, section, row] do
      assert {:error, _} =
               record
               |> Ash.Changeset.for_update(:update, %{name: "Stolen"}, foreign)
               |> Ash.update()

      assert {:error, _} =
               record |> Ash.Changeset.for_destroy(:destroy, %{}, foreign) |> Ash.destroy()
    end

    other_class = class(foreign)
    other_section = P.create_section!(%{class_id: other_class.id, name: "Core"}, foreign)
    assert {:error, _} = P.update_class(other_class, %{studio_id: studio.id}, foreign)
    assert {:error, _} = P.create_section(%{class_id: class.id, name: "Stolen"}, foreign)

    assert {:error, _} =
             P.create_class_exercise(%{section_id: section.id, name: "Stolen"}, foreign)

    assert {:error, _} =
             P.create_class_exercise(
               %{section_id: other_section.id, exercise_id: exercise.id},
               foreign
             )

    assert {:error, _} =
             P.duplicate_class(
               %{source_id: class.id, starts_at: class.starts_at, ends_at: class.ends_at},
               foreign
             )

    assert {:error, _} = P.reorder(%{class_id: class.id, ids: [section.id]}, foreign)
  end

  test "asymmetric ordering, independent duplication and historical snapshots", %{opts: opts} do
    class = class(opts)

    library =
      P.create_exercise!(%{name: "Original chair", cues: "d2u2, pulse", category: "Thighs"}, opts)

    sections =
      for {name, pos} <- [{"Thighs", 0}, {"Seat", 1}, {"Core", 2}],
          do: P.create_section!(%{class_id: class.id, name: name, position: pos}, opts)

    [thighs, seat, core] = sections

    a =
      P.create_class_exercise!(
        %{section_id: thighs.id, exercise_id: library.id, position: 0},
        opts
      )

    b = P.create_class_exercise!(%{section_id: thighs.id, name: "Second", position: 1}, opts)
    c = P.create_class_exercise!(%{section_id: thighs.id, name: "Third", position: 2}, opts)
    P.update_exercise!(library, %{name: "New library name", cues: "New cues"}, opts)
    P.reorder!(%{class_id: class.id, ids: [core.id, thighs.id, seat.id]}, opts)
    P.reorder!(%{class_id: class.id, section_id: thighs.id, ids: [b.id, c.id, a.id]}, opts)

    assert {:error, _} =
             P.reorder(%{class_id: class.id, ids: [core.id, thighs.id, thighs.id]}, opts)

    source = P.get_class!(class.id, Keyword.put(opts, :load, sections: :exercises))
    assert Enum.map(source.sections, & &1.name) == ["Core", "Thighs", "Seat"]

    assert Enum.map(Enum.at(source.sections, 1).exercises, & &1.name) == [
             "Second",
             "Third",
             "Original chair"
           ]

    copy =
      P.duplicate_class!(
        %{
          source_id: class.id,
          starts_at: ~U[2026-12-15 04:30:00Z],
          ends_at: ~U[2026-12-15 05:25:00Z],
          timezone: "America/New_York"
        },
        opts
      )

    copy = P.get_class!(copy.id, Keyword.put(opts, :load, sections: :exercises))
    refute Enum.any?(copy.sections, &(&1.id in Enum.map(source.sections, fn s -> s.id end)))
    copied = Enum.at(copy.sections, 1).exercises |> List.last()
    assert copied.name == "Original chair"
    assert copied.cues == "d2u2, pulse"
    refute copied.id == a.id
    P.update_class_exercise!(copied, %{cues: "Only in copy"}, opts)
    assert Ash.get!(P.ClassExercise, a.id, opts).cues == "d2u2, pulse"
    loaded = P.get_exercise!(library.id, Keyword.put(opts, :load, uses: [section: :class]))

    assert Enum.sort(Enum.map(loaded.uses, & &1.section.class.id)) ==
             Enum.sort([class.id, copy.id])

    P.destroy_exercise!(library, opts)
    preserved = Ash.get!(P.ClassExercise, a.id, opts)
    assert preserved.exercise_id == nil
    assert preserved.name == "Original chair"
    assert preserved.cues == "d2u2, pulse"
    P.destroy_class!(copy, opts)

    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
             Ash.get(P.ClassSection, hd(copy.sections).id, opts)

    assert Ash.get!(P.ClassExercise, a.id, opts).id == a.id
  end

  test "import is explicit, complete and refuses repeats even after deleting an example", %{
    opts: opts
  } do
    assert P.list_classes!(opts) == []
    P.import_examples!(%{}, opts)

    classes =
      P.list_classes!(
        Keyword.merge(opts,
          query: [sort: [starts_at: :asc]],
          load: [:studio, sections: :exercises]
        )
      )

    assert Enum.map(classes, & &1.starts_at) == [
             ~U[2026-05-29 20:15:00Z],
             ~U[2026-07-11 15:30:00Z],
             ~U[2026-09-19 15:30:00Z]
           ]

    assert Enum.map(classes, &DateTime.diff(&1.ends_at, &1.starts_at)) == [3600, 3300, 3300]
    assert Enum.all?(classes, &(&1.timezone == "America/New_York" && is_nil(&1.playlist_url)))
    assert length(P.list_studios!(opts)) == 2
    assert length(P.list_exercises!(opts)) == 18
    assert hd(classes).studio.address =~ "1227 Broadway"
    assert Enum.at(classes, 1).studio.address == nil
    last = List.last(classes)
    assert Enum.map(last.sections, & &1.name) == ["Thighs", "Glutes", "Core"]

    assert Enum.at(last.sections, 1).exercises |> List.last() |> Map.get(:cues) ==
             "circle + reverse, tap lift, knee in 1 back 234, tempo, forward inch, lift tempo"

    assert {:error, _} = P.import_examples(%{}, opts)
    P.destroy_class!(hd(classes), opts)
    assert {:error, _} = P.import_examples(%{}, opts)
    assert length(P.list_classes!(opts)) == 2
    assert length(P.list_exercises!(opts)) == 18
  end

  test "invalid schedules and non-Spotify URLs fail without writes", %{opts: opts} do
    c = class(opts)

    for attrs <- [
          %{ends_at: c.starts_at},
          %{timezone: "Invented/Zone"},
          %{playlist_url: "javascript:alert(1)"},
          %{playlist_url: "https://evil.example/playlist/1"}
        ] do
      assert {:error, _} = P.update_class(c, attrs, opts)
    end

    assert P.get_class!(c.id, opts).ends_at == c.ends_at
  end

  test "blank historical cues remain blank when duplicating after a library update", %{opts: opts} do
    c = class(opts)
    section = P.create_section!(%{class_id: c.id, name: "Core"}, opts)
    library = P.create_exercise!(%{name: "No original cues", category: "Core"}, opts)
    P.create_class_exercise!(%{section_id: section.id, exercise_id: library.id}, opts)
    P.update_exercise!(library, %{cues: "Added later"}, opts)

    copy =
      P.duplicate_class!(%{source_id: c.id, starts_at: c.starts_at, ends_at: c.ends_at}, opts)

    copy = P.get_class!(copy.id, Keyword.put(opts, :load, sections: :exercises))
    assert hd(hd(copy.sections).exercises).cues == nil
  end
end
