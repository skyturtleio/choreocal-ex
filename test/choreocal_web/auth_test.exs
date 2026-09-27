defmodule ChoreocalWeb.AuthTest do
  use ChoreocalWeb.ConnCase
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  alias Choreocal.Accounts.User

  @email "owner@example.test"
  @password "a-test-only-long-passphrase"

  setup do
    :sys.replace_state(Choreocal.AuthRateLimit, fn _ -> %{} end)
    :ok
  end

  defp owner do
    User
    |> Ash.Changeset.for_create(:provision, %{
      email: @email,
      hashed_password: Bcrypt.hash_pwd_salt(@password)
    })
    |> Ash.create!(authorize?: false)
  end

  defp sign_in(conn), do: post(conn, ~p"/sign-in", user: %{email: @email, password: @password})

  defp reset_token(user, lifetime \\ {30, :minutes}) do
    {:ok, token, _} =
      AshAuthentication.Jwt.token_for_user(
        user,
        %{"act" => "reset_password_with_token"},
        purpose: :reset_password_with_token,
        token_lifetime: lifetime
      )

    token
  end

  test "anonymous routes, labels and private registration boundary", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/")) == "/sign-in"
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/")
    document = conn |> get(~p"/sign-in") |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.query(document, "#auth-form input[type=email][autocomplete=email]")
           |> Enum.count() == 1

    assert LazyHTML.query(
             document,
             "#auth-form input[type=password][autocomplete=current-password]"
           )
           |> Enum.count() == 1

    for {method, path} <- [
          {:get, "/register"},
          {:post, "/register"},
          {:post, "/auth/user/password/register"}
        ] do
      assert dispatch(build_conn(), @endpoint, method, path, %{}).status == 404
    end

    refute AshAuthentication.Info.strategy!(User, :password).registration_enabled?

    assert {:error, _} =
             User
             |> Ash.Changeset.for_create(:provision, %{
               email: @email,
               hashed_password: "forbidden"
             })
             |> Ash.create()
  end

  test "wrong password is generic; valid login opens planner and calendar controls work", %{
    conn: conn
  } do
    owner()
    rejected = post(conn, ~p"/sign-in", user: %{email: @email, password: "wrong"})
    assert html_response(rejected, 422) =~ "Email or password was incorrect."
    assert get_session(rejected, "user_token") == nil
    signed = sign_in(conn)
    assert redirected_to(signed) == "/"
    {:ok, view, _} = live(recycle(signed), ~p"/")
    assert has_element?(view, "#calendar-grid button", "1")
    assert has_element?(view, "#sign-out")
    today = Choreocal.Planning.today()
    next = Date.add(Date.end_of_month(today), 1)
    view |> element("#next-month") |> render_click()
    assert has_element?(view, "#calendar-month", Calendar.strftime(next, "%B %Y"))
    selected = Date.add(next, 12)
    view |> element("#day-#{selected}") |> render_click()
    assert has_element?(view, "#selected-date", Calendar.strftime(selected, "%A, %B %-d"))
    view |> element("#today") |> render_click()
    assert has_element?(view, "#day-#{today}[aria-pressed=true]")
  end

  test "logout revokes captured cookie and redirects already open LiveViews", %{conn: conn} do
    owner()
    signed = sign_in(conn)
    captured_cookie = signed.resp_cookies["_choreocal_key"].value
    {:ok, view, _} = live(recycle(signed), ~p"/")
    assert redirected_to(delete(recycle(signed), ~p"/sign-out")) == "/sign-in"
    assert_redirect(view, "/sign-in")
    replay = build_conn() |> put_req_cookie("_choreocal_key", captured_cookie)
    assert redirected_to(get(replay, ~p"/")) == "/sign-in"
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(replay, ~p"/")
  end

  test "reset request does not disclose account existence", %{conn: conn} do
    owner()
    existing = post(conn, ~p"/reset", user: %{email: @email})
    unknown = post(conn, ~p"/reset", user: %{email: "nobody@example.test"})
    assert existing.status == unknown.status
    assert redirected_to(existing) == redirected_to(unknown)

    assert Phoenix.Flash.get(existing.assigns.flash, :info) ==
             Phoenix.Flash.get(unknown.assigns.flash, :info)

    assert_email_sent(fn email ->
      assert email.to == [{"", @email}]
      assert email.text_body =~ "/password-reset/"
      assert email.text_body =~ "30 minutes"
    end)
  end

  test "reset is single use, validates passwords, expires, and revokes old sessions", %{
    conn: conn
  } do
    user = owner()
    signed = sign_in(conn)
    captured_cookie = signed.resp_cookies["_choreocal_key"].value
    {:ok, view, _} = live(recycle(signed), ~p"/")
    token = reset_token(user)
    expired = reset_token(user, {-120, :seconds})

    params = %{
      reset_token: token,
      password: "new-test-only-passphrase",
      password_confirmation: "new-test-only-passphrase"
    }

    assert post(conn, ~p"/password-reset", user: %{params | reset_token: expired}).status == 422

    assert post(conn, ~p"/password-reset",
             user: %{params | password: "short", password_confirmation: "short"}
           ).status == 422

    assert post(conn, ~p"/password-reset", user: %{params | password_confirmation: "different"}).status ==
             422

    assert redirected_to(post(conn, ~p"/password-reset", user: params)) == "/sign-in"
    assert_redirect(view, "/sign-in")
    assert post(conn, ~p"/password-reset", user: params).status == 422
    replay = build_conn() |> put_req_cookie("_choreocal_key", captured_cookie)
    assert redirected_to(get(replay, ~p"/")) == "/sign-in"
    assert sign_in(conn).status == 422

    assert redirected_to(
             post(conn, ~p"/sign-in", user: %{email: @email, password: params.password})
           ) == "/"
  end

  test "private owner provision sends setup mail, can retry, and refuses a second owner" do
    assert :ok = Choreocal.Release.provision(@email)
    assert_email_sent(fn email -> assert email.to == [{"", @email}] end)
    assert :ok = Choreocal.Release.provision(@email)
    assert {:error, :owner_already_exists} = Choreocal.Release.provision("second@example.test")
    assert Ash.count!(User, authorize?: false) == 1
  end

  test "CSRF, health and response privacy", %{conn: conn} do
    assert json_response(get(conn, ~p"/health"), 200) == %{"status" => "ok"}
    response = get(conn, ~p"/sign-in")
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert get_resp_header(response, "referrer-policy") == ["no-referrer"]

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      build_conn()
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
      |> post(~p"/sign-in", user: %{email: @email, password: @password})
    end
  end

  test "reset HTTP admission is bounded before email work", %{conn: conn} do
    for _ <- 1..3, do: assert(post(conn, ~p"/reset", user: %{email: @email}).status == 302)
    limited = post(conn, ~p"/reset", user: %{email: "different@example.test"})
    assert limited.status == 429
    assert get_resp_header(limited, "retry-after") == ["60"]
  end
end
