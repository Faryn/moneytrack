defmodule MoneyTrack.Accounts do
  import Ecto.Query
  alias MoneyTrack.Repo
  alias MoneyTrack.Accounts.{User, Session}
  @session_days 30

  # Administrator entry point only; no public registration endpoint.
  def create_user(attrs), do: %User{} |> User.changeset(attrs) |> Repo.insert()

  def authenticate(username, password) do
    username = User.normalize_username(username)
    user = Repo.get_by(User, username: username)

    if user && is_binary(password) && byte_size(password) in 1..72 do
      if Bcrypt.verify_pass(password, user.hashed_password), do: {:ok, user}, else: :error
    else
      Bcrypt.no_user_verify()
      :error
    end
  end

  def create_session(%User{} = user, kind, label) when kind in ["browser", "device"] do
    raw = :crypto.strong_rand_bytes(32)
    token = Base.url_encode64(raw, padding: false)

    session = %Session{
      user_id: user.id,
      token_hash: :crypto.hash(:sha256, raw),
      kind: kind,
      label: String.slice(label, 0, 100),
      expires_at: DateTime.add(DateTime.utc_now(), @session_days, :day)
    }

    case Repo.insert(session) do
      {:ok, session} -> {:ok, token, session}
      {:error, reason} -> {:error, reason}
    end
  end

  def fetch_session(token, kind) when is_binary(token) and byte_size(token) <= 100 do
    with {:ok, raw} <- Base.url_decode64(token, padding: false), true <- byte_size(raw) == 32 do
      hash = :crypto.hash(:sha256, raw)
      now = DateTime.utc_now()

      case Repo.one(
             from s in Session,
               join: u in User,
               on: u.id == s.user_id,
               where: s.token_hash == ^hash and s.kind == ^kind and s.expires_at > ^now,
               select: {u, s}
           ) do
        {user, session} -> {:ok, user, session}
        nil -> :error
      end
    else
      _ -> :error
    end
  end

  def fetch_session(_, _), do: :error

  def revoke_session(%Session{} = session) do
    Repo.delete_all(
      from s in Session, where: s.id == ^session.id and s.user_id == ^session.user_id
    )

    Phoenix.PubSub.broadcast(MoneyTrack.PubSub, "session:#{session.id}", :session_revoked)
    :ok
  end

  def identity(%User{} = user), do: %{id: user.id, username: user.username}
end
