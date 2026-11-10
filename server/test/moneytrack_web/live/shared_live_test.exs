defmodule MoneyTrackWeb.SharedLiveTest do
  use MoneyTrackWeb.ConnCase
  import Phoenix.LiveViewTest
  import MoneyTrack.Fixtures
  alias MoneyTrack.{Accounts, Ledger, Sharing, Repo}

  test "website shares, accepts, records partial repayment and preserves stale edit draft", %{
    conn: conn
  } do
    a = user()
    b = user()
    email = "#{b.username}@example.org"

    Repo.insert!(%Accounts.VerifiedEmail{
      user_id: b.id,
      address: email,
      verified_at: DateTime.utc_now()
    })

    {category, _} = category(a, "A private restaurants")

    {:ok, expense} =
      Ledger.apply_operation(a, operation("expense", expense(category["entityID"])))

    {:ok, at, _} = Accounts.create_session(a, "browser", "A browser")
    {:ok, bt, _} = Accounts.create_session(b, "browser", "B browser")
    {:ok, av, _} = live(init_test_session(conn, %{session_token: at}), "/shared")

    av
    |> form("#share-form",
      share: %{
        id: expense["entityID"],
        recipientEmail: email,
        creatorSplit: "half",
        paidByCreator: "true"
      }
    )
    |> render_submit()

    assert has_element?(av, "#shared-#{expense["entityID"]}", "Awaiting acceptance")
    {:ok, bv, _} = live(init_test_session(conn, %{session_token: bt}), "/shared")
    bv |> element("#invitation-#{expense["entityID"]} button") |> render_click()
    [connection] = Sharing.snapshot(a).connections
    person = "#person-#{connection["id"]}"
    assert render(av) =~ "Owes you €39.00"
    assert render(bv) =~ "You owe €39.00"
    refute render(bv) =~ "A private restaurants"
    av |> element("#{person} button", "Settle Up") |> render_click()

    av
    |> form("#repayment-form", repayment: %{amount: "15.00", day: "2027-01-01"})
    |> render_submit()

    assert render(av) =~ "Owes you €24.00"
    assert render(bv) =~ "You owe €24.00"
    assert [entry] = Ledger.snapshot(a).expenses
    assert entry.personal_share == 3900

    av
    |> element("#shared-#{expense["entityID"]} button", "Edit Shared Expense")
    |> render_click()

    [current] = Sharing.snapshot(b).expenses

    payload =
      current["payload"]
      |> Map.take(~w(id amount description day paidByCreator creatorSplit))
      |> Map.put("description", "B peer edit")

    assert {:ok, _} =
             Ledger.apply_operation(b, operation("shared_expense", payload, current["revision"]))

    av
    |> form("#shared-edit-form", shared: %{amount: "80.00", description: "A draft"})
    |> render_submit()

    assert has_element?(av, "#sharing-conflict")
    assert has_element?(av, "input[name='shared[description]'][value='A draft']")
    av |> element("#sharing-conflict button", "Keep My Changes") |> render_click()
    assert [updated] = Ledger.snapshot(b).expenses
    assert updated.amount == 8000
    assert updated.description == "A draft"

    assert has_element?(
             av,
             "#shared-#{expense["entityID"]} button[data-confirm*='After deletion: You owe €15.00']"
           )
  end

  test "v1 sync requires upgrade once an account has sharing; v2 remains isolated", %{conn: conn} do
    a = user()
    b = user()
    {cat, _} = category(a)
    {:ok, source} = Ledger.apply_operation(a, operation("expense", expense(cat["entityID"])))

    {:ok, _} =
      Ledger.apply_operation(
        a,
        operation("shared_expense", %{
          "id" => source["entityID"],
          "command" => "share",
          "sourceRevision" => 1,
          "recipientEmail" => "invited@example.org",
          "paidByCreator" => true,
          "creatorSplit" => "half"
        })
      )

    {:ok, token, _} = Accounts.create_session(a, "device", "phone")

    assert conn
           |> put_req_header("authorization", "Bearer " <> token)
           |> get("/api/v1/sync")
           |> json_response(426)

    assert %{"changes" => changes} =
             conn
             |> put_req_header("authorization", "Bearer " <> token)
             |> get("/api/v2/sync")
             |> json_response(200)

    assert Enum.any?(changes, &(&1["entity"] == "shared_expense"))
    {:ok, other, _} = Accounts.create_session(b, "device", "other phone")

    assert %{"changes" => []} =
             conn
             |> put_req_header("authorization", "Bearer " <> other)
             |> get("/api/v2/sync")
             |> json_response(200)
  end
end
