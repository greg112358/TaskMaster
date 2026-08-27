# async: false throughout — SQLite has a single writer, and with
# `transaction_mode: :immediate` every sandbox owner holds the write lock for
# the whole test, so two concurrent tests deadlock even when neither writes.
defmodule TaskmasterWeb.ErrorJSONTest do
  use TaskmasterWeb.ConnCase, async: false

  test "renders 404" do
    assert TaskmasterWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert TaskmasterWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
