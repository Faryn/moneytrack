defmodule MoneyTrack.Sharing.InvitationReceipt do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sharing_invitation_receipts" do
    field :expense_id, :binary_id
    field :user_id, :binary_id
    field :revision, :integer
  end
end
