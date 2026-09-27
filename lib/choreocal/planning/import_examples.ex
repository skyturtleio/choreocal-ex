defmodule Choreocal.Planning.ImportExamples do
  @moduledoc "The three owner-provided plans, preserving their original shorthand and New York times."
  use Ash.Resource.Change
  alias Choreocal.Planning

  def change(changeset, _, context) do
    Ash.Changeset.after_action(changeset, fn _, receipt ->
      opts = [actor: context.actor]

      exhale =
        Planning.create_studio!(
          %{
            name: "exhale",
            address: "Virgin Hotels\n1227 Broadway\nNew York NY 10001\nUnited States"
          },
          opts
        )

      tyr = Planning.create_studio!(%{name: "The Yoga Room (tyr)"}, opts)

      Enum.each(examples(), fn {name, studio, date, start, finish, playlist, sections} ->
        class =
          Planning.create_class!(
            %{
              name: name,
              studio_id: if(studio == :exhale, do: exhale.id, else: tyr.id),
              starts_at: utc(date, start),
              ends_at: utc(date, finish),
              timezone: "America/New_York",
              playlist_name: playlist
            },
            opts
          )

        Enum.with_index(sections, fn {category, exercises}, index ->
          section =
            Planning.create_section!(%{class_id: class.id, name: category, position: index}, opts)

          Enum.with_index(exercises, fn {name, cues}, position ->
            exercise =
              Planning.create_exercise!(%{name: name, cues: cues, category: category}, opts)

            Planning.create_class_exercise!(
              %{section_id: section.id, exercise_id: exercise.id, position: position},
              opts
            )
          end)
        end)
      end)

      {:ok, receipt}
    end)
  end

  defp utc(date, time) do
    date
    |> NaiveDateTime.new!(time)
    |> DateTime.from_naive!("America/New_York", Tzdata.TimeZoneDatabase)
    |> DateTime.shift_zone!("Etc/UTC", Tzdata.TimeZoneDatabase)
  end

  defp examples do
    [
      {"exhale", :exhale, ~D[2026-05-29], ~T[16:15:00], ~T[17:15:00], "exhale 4",
       [
         {"Thighs",
          [{"Together chair", nil}, {"Profile high v tube", nil}, {"Wide 2nd face center", nil}]},
         {"Seat",
          [
            {"Standing profile pretzel ball",
             "lift hold, d2u2, tempo, press back hold, 1squeeze1lift, together"},
            {"Semi fold",
             "du, 1lift1pulse, together, bend extend, 3/4 1lift1pulse, pulse lift together"}
          ]},
         {"Core", [{"RB w/ long band", nil}]}
       ]},
      {"tyr", :tyr, ~D[2026-07-11], ~T[11:30:00], ~T[12:25:00], "exhale 5",
       [
         {"Thighs", [{"Kneeling", nil}, {"Rb extension TO", nil}, {"Hip width ball", nil}]},
         {"Seat",
          [
            {"Semi fold box knee in TO",
             "uphold, d1u3, tempo, circle+reverse, knee in uphold, tempo"},
            {"TT ball",
             "squeeze in in release, up up release, each, d2u2, tempo, squeeze lift + hand on bicep"}
          ]},
         {"Core", [{"exhale core+ball", nil}]}
       ]},
      {"tyr", :tyr, ~D[2026-09-19], ~T[11:30:00], ~T[12:25:00], "exhale 5",
       [
         {"Thighs",
          [
            {"4th face center", "inch, straight bend, chair2, pulse"},
            {"Profile hip width",
             "heels lower lift, legs extend bend, calf raises, pulse down hold, tuck release, pulse tempo"},
            {"Low v waterski tube", nil}
          ]},
         {"Glutes",
          [
            {"Profile arm long hipwidth 3/4",
             "backback hold, tempo, heel in for 2 to 3/4, tempo, arms pull back 2, hold low press back tempo"},
            {"TTTO back diagonal long",
             "circle + reverse, tap lift, knee in 1 back 234, tempo, forward inch, lift tempo"}
          ]},
         {"Core", [{"band on barre", nil}]}
       ]}
    ]
  end
end
